#!/bin/sh
set -eux

LOCALPRIVATEKEYFILE=/etc/wireguard/extra.key
PRESHAREDKEYFILE=/etc/wireguard/extra.presharedkey
PEERPUBLICKEY='public key from wireguard config'
ENDPOINT_IP='ip from wireguard config'
ENDPOINT_PORT='port from wireguard config'
ENDPOINT="$ENDPOINT_IP:$ENDPOINT_PORT"
WGADDRESS='address from wireguard config'

# Clean up (ignore errors)
ip link del wg-vpn 2>/dev/null || true
ip -n vpn link del wg-vpn 2>/dev/null || true
ip netns add vpn 2>/dev/null || true

# Create WG on host, then move into namespace
ip link add dev wg-vpn type wireguard
ip link set dev wg-vpn netns vpn

# Bring lo up inside namespace
ip -n vpn link set lo up

# Configure WireGuard (keys/peer/endpoint/allowedips)
ip netns exec vpn wg set wg-vpn \
  private-key "$LOCALPRIVATEKEYFILE" \
  peer "$PEERPUBLICKEY" \
  preshared-key "$PRESHAREDKEYFILE" \
  endpoint "$ENDPOINT" \
  allowed-ips 0.0.0.0/0,::/0 \
  persistent-keepalive 25

# IMPORTANT: assign the tunnel IPs from your *client config*
# (Replace these with your real Address= values)
ip -n vpn addr add $WGADDRESS/32 dev wg-vpn
# ip -n vpn addr add fc01::2/64 dev wg-vpn 2>/dev/null || true

# Bring WG link up (after config + addresses)
ip -n vpn link set wg-vpn up


# Create veth uplink if it doesn't exist
ip link show veth-host >/dev/null 2>&1 || ip link add veth-host type veth peer name veth-vpn
ip link set veth-host up
ip addr add 10.200.200.1/24 dev veth-host 2>/dev/null || true

ip link set veth-vpn netns vpn 2>/dev/null || true
ip -n vpn addr add 10.200.200.2/24 dev veth-vpn 2>/dev/null || true
ip -n vpn link set veth-vpn up

# Host NAT/forwarding (idempotency not perfect with raw iptables)
sysctl -w net.ipv4.ip_forward=1 >/dev/null
WAN_IF="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
iptables -t nat -C POSTROUTING -s 10.200.200.0/24 -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.200.200.0/24 -o "$WAN_IF" -j MASQUERADE
iptables -C FORWARD -i veth-host -j ACCEPT 2>/dev/null || iptables -A FORWARD -i veth-host -j ACCEPT
iptables -C FORWARD -o veth-host -j ACCEPT 2>/dev/null || iptables -A FORWARD -o veth-host -j ACCEPT

# Ensure the endpoint goes OUT via veth (bootstrap path)
ip -n vpn route replace "$ENDPOINT_IP"/32 via 10.200.200.1 dev veth-vpn

# Now route everything else through the VPN
ip -n vpn route replace default dev wg-vpn
ip -n vpn -6 route replace default dev wg-vpn 2>/dev/null || true