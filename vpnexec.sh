#!/bin/sh

set -eu

ns="vpn"
run_user="${SUDO_USER:-$USER}"
run_uid="$(id -u "$run_user")"

keep_env="DISPLAY,XAUTHORITY,WAYLAND_DISPLAY,XDG_SESSION_TYPE,DBUS_SESSION_BUS_ADDRESS"

exec ip netns exec "$ns" sh -eu -c '
  # Mount cgroups for snap support https://forum.snapcraft.io/t/solved-launching-snaps-in-network-namespace-fails-with-error-cannot-find-tracking-cgroup/31113/3
  mountpoint -q /sys/fs/cgroup || mount -t cgroup2 cgroup2 /sys/fs/cgroup
  mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security

  export XDG_RUNTIME_DIR="/run/user/'"$run_uid"'"

  # If sudo stripped XAUTHORITY, fall back to the user's ~/.Xauthority
  if [ -z "${XAUTHORITY:-}" ]; then
    XAUTHORITY="/home/'"$run_user"'/.Xauthority"
    export XAUTHORITY
  fi

  exec sudo -u '"$run_user"' \
    --preserve-env='"$keep_env"',"XDG_RUNTIME_DIR" \
    -- "$@"
' sh "$@"

