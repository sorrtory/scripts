#!/usr/bin/env bash
set -euo pipefail

# vpn.sh — WireGuard-backed network namespace runner
#
# DNS modes (mutually exclusive):
#   default: direct (DNS1/DNS2) in /etc/netns/vpn/resolv.conf
#   -d: dnsmasq stub inside netns (127.0.0.53) -> forwards to DNS1/DNS2
#   -r: resolved-uplink fallback:
#        - copies nameserver/search lines from /run/systemd/resolve/resolv.conf into /etc/netns/vpn/resolv.conf
#        - adds routes for those nameservers via veth (so they work even with default route via wg)
#        - optionally switches host /etc/resolv.conf symlink to /run/systemd/resolve/resolv.conf (BACKED UP + RESTORABLE)
#
# Other:
#   -D: stop/kill dnsmasq AND restore host /etc/resolv.conf to original (if backed up) AND set DNS back to direct
#   -g: snap-friendly GUI runner (private mount ns; overlays resolv.conf; mounts cgroup2/securityfs)
#   -t: connectivity + DNS leak risk checks + prints current external IP
#   --config/-C: use non-default WireGuard config path
#   --clean/-c: cleanup everything (includes -D behavior)

# ─── Defaults ────────────────────────────────────────────────────────────────
NS="vpn"
WG_IF="wg-vpn"
VETH_HOST="veth-host"
VETH_NS="veth-vpn"

VETH_HOST_IP4="10.200.200.1"
VETH_NS_IP4="10.200.200.2"
VETH_SUBNET4="10.200.200.0/24"

# Optional v6 on veth (only used for routing v6 nameservers in -r mode if present)
VETH_HOST_IP6="fd00:200:200::1"
VETH_NS_IP6="fd00:200:200::2"
VETH_SUBNET6="fd00:200:200::/64"

WG_CONF="/etc/wireguard/extra.conf"

DNS_DIR="/etc/netns/${NS}"
DNS_FILE="${DNS_DIR}/resolv.conf"

DNS1="1.1.1.1"
DNS2="8.8.8.8"
DNS_STUB="127.0.0.53"
RESOLVED_UPLINK="/run/systemd/resolve/resolv.conf"

DNSMASQ_PIDFILE="/run/${NS}-dnsmasq.pid"
WAN_IF_FILE="/run/${NS}-wan-if"

# host /etc/resolv.conf backup (only created when -r needs to touch it)
HOST_RESOLV_META="/run/${NS}-host-resolv.meta"
HOST_RESOLV_DATA="/run/${NS}-host-resolv.data"

# ─────────────────────────────────────────────────────────────────────────────
DO_TEST=0
DO_GUI=0
DO_STOP_DNS=0
DO_CLEAN=0
DNS_MODE="direct"   # direct | dnsmasq | resolved
TOUCH_HOST_RESOLV=0 # set to 1 only in -r mode

# ─── Colors & logging ────────────────────────────────────────────────────────
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  RESET="$(tput sgr0)"
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

ok()   { echo >&2 "${GREEN}$*${RESET}"; }
warn() { echo >&2 "${YELLOW}$*${RESET}"; }
err()  { echo >&2 "${RED}$*${RESET}"; }
die()  { err "Error: $*"; exit 1; }

usage() {
  local me
  me="$(basename "$0")"
  cat >&2 <<EOF
Usage:
  $me [options] [--] <command> [args...]
  $me [options] -t
  $me -h

Options:
  --config <path>, -C <path>   WireGuard config path (default: $WG_CONF)
  --clean, -c                  Cleanup everything (includes -D behavior)

DNS (mutually exclusive):
  (default)                    direct: ${DNS1}, ${DNS2}
  -d                           dnsmasq stub: ${DNS_STUB} inside netns -> forwards to ${DNS1}, ${DNS2}
  -r                           resolved-uplink fallback: uses ${RESOLVED_UPLINK}
                               also routes uplink nameservers via veth (fallback; may leak DNS)

Other:
  -D                           Stop/kill dnsmasq + restore host /etc/resolv.conf (if backed up) + set DNS back to direct
  -g                           GUI mode (snap-friendly): private mount ns + resolv overlay
  -t                           Test connectivity + print current external IP + DNS leak risk check
  -h, --help                   Help

Examples:
  sudo $me curl https://example.com
  sudo $me -d curl https://example.com
  sudo $me -g -d firefox
  sudo $me -r -g firefox
  sudo $me -D
  sudo $me --clean
EOF
}

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "must run as root (use sudo)"
}

netns_exists() {
  ip netns list | awk '{print $1}' | grep -qx "$NS"
}

detect_wan_if() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# ─── Host /etc/resolv.conf backup/restore ────────────────────────────────────
backup_host_resolv_conf() {
  [[ "$TOUCH_HOST_RESOLV" -eq 1 ]] || return 0
  [[ -e "$HOST_RESOLV_META" ]] && return 0

  if [[ -L /etc/resolv.conf ]]; then
    local target
    target="$(readlink /etc/resolv.conf || true)"
    echo "symlink $target" >"$HOST_RESOLV_META"
    ok "Backed up host /etc/resolv.conf symlink -> $target"
  else
    echo "file" >"$HOST_RESOLV_META"
    cp -a /etc/resolv.conf "$HOST_RESOLV_DATA"
    ok "Backed up host /etc/resolv.conf file to $HOST_RESOLV_DATA"
  fi
}

restore_host_resolv_conf() {
  [[ -e "$HOST_RESOLV_META" ]] || { warn "No host /etc/resolv.conf backup found; nothing to restore"; return 0; }

  local kind rest
  kind="$(awk '{print $1}' "$HOST_RESOLV_META" 2>/dev/null || true)"
  rest="$(cut -d' ' -f2- "$HOST_RESOLV_META" 2>/dev/null || true)"

  if [[ "$kind" == "symlink" ]]; then
    [[ -n "$rest" ]] || { warn "Backup metadata incomplete; cannot restore symlink"; return 0; }
    rm -f /etc/resolv.conf
    ln -sf "$rest" /etc/resolv.conf
    ok "Restored host /etc/resolv.conf symlink -> $rest"
  elif [[ "$kind" == "file" ]]; then
    [[ -f "$HOST_RESOLV_DATA" ]] || { warn "Backup file missing; cannot restore /etc/resolv.conf"; return 0; }
    rm -f /etc/resolv.conf
    cp -a "$HOST_RESOLV_DATA" /etc/resolv.conf
    ok "Restored host /etc/resolv.conf file from backup"
  else
    warn "Unknown backup kind '$kind'; cannot restore"
    return 0
  fi

  rm -f "$HOST_RESOLV_META" "$HOST_RESOLV_DATA" 2>/dev/null || true
}

set_host_resolv_to_uplink() {
  [[ "$TOUCH_HOST_RESOLV" -eq 1 ]] || return 0
  [[ -r "$RESOLVED_UPLINK" ]] || die "resolved uplink not readable: $RESOLVED_UPLINK"

  backup_host_resolv_conf
  rm -f /etc/resolv.conf
  ln -sf "$RESOLVED_UPLINK" /etc/resolv.conf
  warn "Host /etc/resolv.conf set to -> $RESOLVED_UPLINK (restorable via -D/--clean)"
}

# ─── DNS config in /etc/netns/vpn/resolv.conf ────────────────────────────────
write_resolv_direct() {
  mkdir -p "$DNS_DIR"
  cat >"$DNS_FILE" <<EOF
# managed by vpn.sh (mode=direct)
nameserver ${DNS1}
nameserver ${DNS2}
EOF
  ok "DNS mode: direct (${DNS1}, ${DNS2})"
}

write_resolv_dnsmasq() {
  mkdir -p "$DNS_DIR"
  cat >"$DNS_FILE" <<EOF
# managed by vpn.sh (mode=dnsmasq)
nameserver ${DNS_STUB}
EOF
  ok "DNS mode: dnsmasq stub (${DNS_STUB})"
}

write_resolv_resolved_copy() {
  mkdir -p "$DNS_DIR"
  [[ -r "$RESOLVED_UPLINK" ]] || die "resolved uplink not readable: $RESOLVED_UPLINK"

  {
    echo "# managed by vpn.sh (mode=resolved-copy from $RESOLVED_UPLINK)"
    # keep nameserver + search lines; ignore comments
    awk '
      /^nameserver[[:space:]]+/ {print; next}
      /^search[[:space:]]+/ {print; next}
      /^options[[:space:]]+/ {print; next}
    ' "$RESOLVED_UPLINK" | sed '/^[[:space:]]*$/d'
  } >"$DNS_FILE"

  warn "DNS mode: resolved uplink (copied from $RESOLVED_UPLINK)"
  warn "This can leak DNS if uplink nameservers are LAN resolvers (routes will be added via veth)."
}

ensure_dns_file() {
  case "$DNS_MODE" in
    direct)   write_resolv_direct ;;
    dnsmasq)  write_resolv_dnsmasq ;;
    resolved) write_resolv_resolved_copy ;;
    *) die "unknown DNS_MODE=$DNS_MODE" ;;
  esac
}

# ─── dnsmasq in netns ────────────────────────────────────────────────────────
dnsmasq_listening() {
  ip netns exec "$NS" sh -lc 'ss -H -lunp sport = :53 2>/dev/null' \
    | grep -qE "(127\.0\.0\.53|${DNS_STUB}).*:53"
}

ensure_dnsmasq() {
  [[ "$DNS_MODE" == "dnsmasq" ]] || return 0
  command -v dnsmasq >/dev/null 2>&1 || die "dnsmasq not found. Install: sudo apt install dnsmasq"

  if [[ -s "$DNSMASQ_PIDFILE" ]]; then
    local pid
    pid="$(cat "$DNSMASQ_PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      if dnsmasq_listening; then
        warn "dnsmasq already running (pid $pid)"
        return 0
      fi
      warn "dnsmasq pid $pid exists but no listener on ${DNS_STUB}:53; restarting"
      stop_dnsmasq || true
    else
      rm -f "$DNSMASQ_PIDFILE" 2>/dev/null || true
    fi
  fi

  ip netns exec "$NS" dnsmasq \
    --pid-file="$DNSMASQ_PIDFILE" \
    --listen-address="$DNS_STUB" \
    --bind-interfaces \
    --port=53 \
    --no-resolv \
    --server="$DNS1" \
    --server="$DNS2" \
    --cache-size=1000 \
    --log-facility=/dev/null

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    dnsmasq_listening && break
    sleep 0.05
  done

  if dnsmasq_listening; then
    ok "Started dnsmasq in netns '$NS' (listening on ${DNS_STUB}:53)"
  else
    err "dnsmasq did not start listening on ${DNS_STUB}:53; falling back to direct DNS"
    DNS_MODE="direct"
    write_resolv_direct
  fi
}

stop_dnsmasq() {
  if [[ -s "$DNSMASQ_PIDFILE" ]]; then
    local pid
    pid="$(cat "$DNSMASQ_PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
      done
      kill -9 "$pid" 2>/dev/null || true
      ok "Stopped dnsmasq (pid $pid)"
    fi
    rm -f "$DNSMASQ_PIDFILE" 2>/dev/null || true
  else
    warn "dnsmasq pidfile not found ($DNSMASQ_PIDFILE)"
  fi
}

# ─── Add routes for resolved-uplink nameservers via veth (fallback mode) ─────
ensure_resolved_routes() {
  [[ "$DNS_MODE" == "resolved" ]] || return 0

  local ns
  while read -r ns; do
    [[ -n "$ns" ]] || continue
    if [[ "$ns" == *:* ]]; then
      ip -n "$NS" -6 route replace "${ns}/128" via "$VETH_HOST_IP6" dev "$VETH_NS" 2>/dev/null || true
    else
      ip -n "$NS" route replace "${ns}/32" via "$VETH_HOST_IP4" dev "$VETH_NS" 2>/dev/null || true
    fi
  done < <(awk '/^nameserver[[:space:]]+/ {print $2}' "$DNS_FILE" 2>/dev/null | xargs -n1)

  ok "Added routes for resolved-uplink nameservers via $VETH_NS (fallback mode)"
}

# ─── WG config parsing ───────────────────────────────────────────────────────
get_field() {
  local section="$1" key="$2"
  awk -v sec="$section" -v key="$key" '
    /^\[/ { insec = ($0 == "["sec"]"); next }
    insec && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print; exit
    }
  ' "$WG_CONF"
}

setup_namespace() {
  [[ -f "$WG_CONF" ]] || die "config not found: $WG_CONF"

  local WG_PRIVATEKEY WG_ADDRESS PEERPUBLICKEY WG_PRESHAREDKEY WG_ENDPOINT
  WG_PRIVATEKEY="$(get_field Interface PrivateKey)"
  WG_ADDRESS="$(get_field Interface Address)"
  PEERPUBLICKEY="$(get_field Peer PublicKey)"
  WG_PRESHAREDKEY="$(get_field Peer PresharedKey)"
  WG_ENDPOINT="$(get_field Peer Endpoint)"

  [[ -n "$WG_PRIVATEKEY" && -n "$WG_ADDRESS" && -n "$PEERPUBLICKEY" && -n "$WG_ENDPOINT" ]] || \
    die "missing required fields (PrivateKey/Address/PublicKey/Endpoint) in $WG_CONF"

  local ENDPOINT_HOST ENDPOINT_PORT ENDPOINT_IS_V6=0
  if [[ "$WG_ENDPOINT" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
    ENDPOINT_HOST="${BASH_REMATCH[1]}"
    ENDPOINT_PORT="${BASH_REMATCH[2]}"
    ENDPOINT_IS_V6=1
  elif [[ "$WG_ENDPOINT" =~ ^([^:]+):([0-9]+)$ ]]; then
    ENDPOINT_HOST="${BASH_REMATCH[1]}"
    ENDPOINT_PORT="${BASH_REMATCH[2]}"
  else
    die "unrecognized endpoint format: $WG_ENDPOINT"
  fi

  ip netns add "$NS"
  ip -n "$NS" link set lo up

  ip link add dev "$WG_IF" type wireguard
  ip link set dev "$WG_IF" netns "$NS"

  local PRESHARED_KEY_ARGS=()
  [[ -n "${WG_PRESHAREDKEY:-}" ]] && PRESHARED_KEY_ARGS=(preshared-key /dev/fd/4)

  ip netns exec "$NS" \
    wg set "$WG_IF" \
      private-key /dev/fd/3 \
      peer "$PEERPUBLICKEY" \
        "${PRESHARED_KEY_ARGS[@]}" \
        endpoint "${ENDPOINT_HOST}:${ENDPOINT_PORT}" \
        allowed-ips 0.0.0.0/0,::/0 \
        persistent-keepalive 25 \
    3<<<"$WG_PRIVATEKEY" 4<<<"${WG_PRESHAREDKEY:-}"

  IFS=',' read -ra ADDRS <<<"$WG_ADDRESS"
  for a in "${ADDRS[@]}"; do
    a="$(echo "$a" | xargs)"
    [[ -n "$a" ]] || continue
    if [[ "$a" == *:* ]]; then
      [[ "$a" == */* ]] && ip -n "$NS" -6 addr replace "$a" dev "$WG_IF" || ip -n "$NS" -6 addr replace "${a}/128" dev "$WG_IF"
    else
      [[ "$a" == */* ]] && ip -n "$NS" addr replace "$a" dev "$WG_IF" || ip -n "$NS" addr replace "${a}/32" dev "$WG_IF"
    fi
  done

  ip -n "$NS" link set "$WG_IF" up

  ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
  ip link set "$VETH_HOST" up
  ip addr replace "${VETH_HOST_IP4}/24" dev "$VETH_HOST"
  ip -6 addr replace "${VETH_HOST_IP6}/64" dev "$VETH_HOST" 2>/dev/null || true

  ip link set "$VETH_NS" netns "$NS"
  ip -n "$NS" addr replace "${VETH_NS_IP4}/24" dev "$VETH_NS"
  ip -n "$NS" -6 addr replace "${VETH_NS_IP6}/64" dev "$VETH_NS" 2>/dev/null || true
  ip -n "$NS" link set "$VETH_NS" up

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null || true

  local WAN_IF
  WAN_IF="$(detect_wan_if)"
  [[ -n "$WAN_IF" ]] || die "could not determine WAN interface"
  echo "$WAN_IF" >"$WAN_IF_FILE"
  ok "Detected WAN interface: $WAN_IF"

  iptables -t nat -C POSTROUTING -s "$VETH_SUBNET4" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "$VETH_SUBNET4" -o "$WAN_IF" -j MASQUERADE

  iptables -C FORWARD -i "$VETH_HOST" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$VETH_HOST" -j ACCEPT
  iptables -C FORWARD -o "$VETH_HOST" -j ACCEPT 2>/dev/null || iptables -A FORWARD -o "$VETH_HOST" -j ACCEPT

  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t nat -C POSTROUTING -s "$VETH_SUBNET6" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
      ip6tables -t nat -A POSTROUTING -s "$VETH_SUBNET6" -o "$WAN_IF" -j MASQUERADE
  fi

  if [[ "$ENDPOINT_IS_V6" -eq 1 ]]; then
    ip -n "$NS" -6 route replace "${ENDPOINT_HOST}/128" via "$VETH_HOST_IP6" dev "$VETH_NS"
  else
    ip -n "$NS" route replace "${ENDPOINT_HOST}/32" via "$VETH_HOST_IP4" dev "$VETH_NS"
  fi

  ip -n "$NS" route replace default dev "$WG_IF"
  ip -n "$NS" -6 route replace default dev "$WG_IF" 2>/dev/null || true

  ok "Created namespace '$NS' from $WG_CONF"
}

# ─── Cleanup ────────────────────────────────────────────────────────────────
cleanup_all() {
  warn "Cleaning up namespace '$NS'..."

  # include -D behavior
  stop_dnsmasq || true
  restore_host_resolv_conf || true
  write_resolv_direct || true

  local WAN_IF=""
  [[ -s "$WAN_IF_FILE" ]] && WAN_IF="$(cat "$WAN_IF_FILE" 2>/dev/null || true)"
  [[ -n "${WAN_IF:-}" ]] || WAN_IF="$(detect_wan_if || true)"

  if [[ -n "${WAN_IF:-}" ]]; then
    iptables -t nat -C POSTROUTING -s "$VETH_SUBNET4" -o "$WAN_IF" -j MASQUERADE 2>/dev/null && \
      iptables -t nat -D POSTROUTING -s "$VETH_SUBNET4" -o "$WAN_IF" -j MASQUERADE || true
  fi
  iptables -C FORWARD -i "$VETH_HOST" -j ACCEPT 2>/dev/null && iptables -D FORWARD -i "$VETH_HOST" -j ACCEPT || true
  iptables -C FORWARD -o "$VETH_HOST" -j ACCEPT 2>/dev/null && iptables -D FORWARD -o "$VETH_HOST" -j ACCEPT || true

  if command -v ip6tables >/dev/null 2>&1 && [[ -n "${WAN_IF:-}" ]]; then
    ip6tables -t nat -C POSTROUTING -s "$VETH_SUBNET6" -o "$WAN_IF" -j MASQUERADE 2>/dev/null && \
      ip6tables -t nat -D POSTROUTING -s "$VETH_SUBNET6" -o "$WAN_IF" -j MASQUERADE || true
  fi

  ip -n "$NS" link del "$WG_IF" 2>/dev/null || true
  ip link del "$WG_IF" 2>/dev/null || true
  ip link del "$VETH_HOST" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true

  rm -f "$WAN_IF_FILE" 2>/dev/null || true
  rm -f "$DNSMASQ_PIDFILE" 2>/dev/null || true
  rm -rf "$DNS_DIR" 2>/dev/null || true

  ok "Cleanup complete."
}

# ─── DNS leak risk check ─────────────────────────────────────────────────────
dns_leak_risk_check() {
  echo >&2 "DNS leak risk check:"
  local nslist
  nslist="$(ip netns exec "$NS" awk '/^nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf 2>/dev/null || true)"

  if [[ -z "${nslist:-}" ]]; then
    warn "  No nameservers found in /etc/resolv.conf inside netns"
    return 0
  fi

  local nsip dev
  while read -r nsip; do
    [[ -n "$nsip" ]] || continue

    if [[ "$nsip" == "127."* || "$nsip" == "::1" ]]; then
      warn "  nameserver $nsip (localhost) — OK only if a resolver runs inside the namespace (dnsmasq/systemd-resolved)"
    fi

    if [[ "$nsip" == *:* ]]; then
      dev="$(ip -n "$NS" -6 route get "$nsip" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    else
      dev="$(ip -n "$NS" route get "$nsip" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    fi

    if [[ -z "${dev:-}" ]]; then
      warn "  nameserver $nsip — could not determine route (might fail)"
      continue
    fi

    if [[ "$dev" == "$WG_IF" ]]; then
      ok "  nameserver $nsip — routed via $dev (tunnel)"
    elif [[ "$dev" == "$VETH_NS" ]]; then
      warn "  nameserver $nsip — routed via $dev (may leak via host path)"
    else
      warn "  nameserver $nsip — routed via $dev (verify)"
    fi
  done <<<"$nslist"
}

# ─── External IP / test ──────────────────────────────────────────────────────
get_external_ip() {
  local url="$1"
  ip netns exec "$NS" curl -fsS --max-time 5 "$url" 2>/dev/null | xargs || true
}

run_test() {
  echo >&2 "Connectivity test:"
  ok "  2ip.ru  : $(ip netns exec "$NS" curl -fsS --max-time 5 https://2ip.ru 2>/dev/null || echo "failed")"
  ok "  ident.me: $(ip netns exec "$NS" curl -fsS --max-time 5 https://ident.me 2>/dev/null || echo "failed")"

  echo >&2 "Resolver view inside netns:"
  ip netns exec "$NS" sh -lc 'echo "  /etc/resolv.conf:"; sed "s/^/    /" /etc/resolv.conf' 2>/dev/null || true

  if [[ "$DNS_MODE" == "dnsmasq" ]]; then
    dnsmasq_listening && ok "dnsmasq is listening on ${DNS_STUB}:53" || warn "dnsmasq is not listening on ${DNS_STUB}:53"
  fi

  echo >&2 "Host /etc/resolv.conf:"
  if [[ -L /etc/resolv.conf ]]; then
    ok "  symlink -> $(readlink /etc/resolv.conf)"
  else
    warn "  not a symlink (regular file)"
  fi

  dns_leak_risk_check
}

# ─── GUI runner (snap-friendly; your working base + symlink-safe source) ─────
run_in_ns_gui() {
  command -v unshare >/dev/null 2>&1 || die "'unshare' not found (install util-linux)"

  local run_user run_uid keep_env
  run_user="${SUDO_USER:-$USER}"
  run_uid="$(id -u "$run_user")"
  keep_env="DISPLAY,XAUTHORITY,WAYLAND_DISPLAY,XDG_SESSION_TYPE,DBUS_SESSION_BUS_ADDRESS,XDG_RUNTIME_DIR"

  RESOLV_SRC="$DNS_FILE" RUN_USER="$run_user" RUN_UID="$run_uid" KEEP_ENV="$keep_env" \
  exec ip netns exec "$NS" unshare -m sh -eu -c '
    mount --make-rprivate /

    mountpoint -q /sys/fs/cgroup || mount -t cgroup2 cgroup2 /sys/fs/cgroup
    mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security

    test -r "$RESOLV_SRC" || { echo "Error: cannot read $RESOLV_SRC" >&2; exit 1; }

    # If RESOLV_SRC is a symlink, bind-mount the real target file (more reliable for snaps)
    SRC="$(readlink -f "$RESOLV_SRC" 2>/dev/null || echo "$RESOLV_SRC")"

    mount --bind --no-canonicalize "$SRC" /etc/resolv.conf

    if [ -e /run/systemd/resolve/stub-resolv.conf ]; then
      mount --bind "$SRC" /run/systemd/resolve/stub-resolv.conf 2>/dev/null || true
    fi
    if [ -e /run/systemd/resolve/resolv.conf ]; then
      mount --bind "$SRC" /run/systemd/resolve/resolv.conf 2>/dev/null || true
    fi

    export XDG_RUNTIME_DIR="/run/user/$RUN_UID"
    if [ -z "${XAUTHORITY:-}" ]; then
      export XAUTHORITY="/home/$RUN_USER/.Xauthority"
    fi

    exec sudo -H -u "$RUN_USER" --preserve-env="$KEEP_ENV" -- "$@"
  ' sh "$@"
}

# ─── Arg parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --config|-C)
      [[ $# -ge 2 ]] || die "$1 requires a path"
      WG_CONF="$2"; shift 2 ;;
    --clean|-c)
      DO_CLEAN=1; shift ;;
    -t) DO_TEST=1; shift ;;
    -g) DO_GUI=1; shift ;;
    -d)
      [[ "$DNS_MODE" == "direct" ]] || die "DNS modes are mutually exclusive; do not combine -d with -r"
      DNS_MODE="dnsmasq"
      shift ;;
    -r)
      [[ "$DNS_MODE" == "direct" ]] || die "DNS modes are mutually exclusive; do not combine -r with -d"
      DNS_MODE="resolved"
      TOUCH_HOST_RESOLV=1
      shift ;;
    -D)
      DO_STOP_DNS=1; shift ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

need_root

if [[ "$DO_CLEAN" -eq 1 ]]; then
  cleanup_all
  exit 0
fi

if [[ "$DO_STOP_DNS" -eq 1 ]]; then
  stop_dnsmasq
  restore_host_resolv_conf || true
  DNS_MODE="direct"
  ensure_dns_file
  exit 0
fi

# Ensure namespace exists
if ! netns_exists; then
  setup_namespace
else
  warn "Namespace '$NS' already exists; skipping setup"
fi

# In -r mode, switch host resolv.conf to uplink (backup+restore supported)
set_host_resolv_to_uplink

# Apply DNS mode and any dependencies
ensure_dns_file
ensure_dnsmasq
ensure_resolved_routes

if [[ "$DO_TEST" -eq 1 ]]; then
  run_test
  exit 0
fi

if [[ $# -eq 0 ]]; then
  die "no command specified. Use -t for test or provide a command."
fi

if [[ "$DO_GUI" -eq 1 ]]; then
  run_in_ns_gui "$@"
else
  exec ip netns exec "$NS" "$@"
fi