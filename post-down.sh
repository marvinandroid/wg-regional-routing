#!/bin/bash
# MIT License
# 
# Copyright (c) 2024 Alexander @androidparanoid
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

which tee > /dev/null || { echo "tee not found"; exit 1; }
which ip > /dev/null || { echo "ip command not found"; exit 1; }
which jq > /dev/null || { echo "jq not found"; exit 1; }

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%SZ%z') - post-up - ${1^^} - $2" | tee -a "wg-post-hooks.log"
}

IFACE=$(ip -j route | jq -r '.[] | select(.dst == "default") | .dev')
VPN_NET="172.16.1.0/24"
VPN6_NET="fd70:ffff:6600::/64"
SOURCE_ADDR=$(ip -j addr show $IFACE | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')

[ -z "$IFACE" ] && { log error "Unable to retrieve default network interface name"; exit 2; }
[ -z "$SOURCE_ADDR" ] &&  { log error "Unable to retrieve source IP address"; exit 2; }

log info "Deleting accept IPv4 rule"
iptables -D FORWARD -i $1 -j ACCEPT
log info "Deleting rule to avoid connectivity loss"
ip rule del from $SOURCE_ADDR table main
log info "Deleting NAT IPv4 and masquerading"
iptables -t nat -D POSTROUTING -o $IFACE -s $VPN_NET -j MASQUERADE
log info "Deleting accept IPv6 rule"
ip6tables -D FORWARD -i $1 -j ACCEPT
log info "Deleting NAT IPv6 and masquerading"
ip6tables -t nat -D POSTROUTING -o $IFACE -s $VPN6_NET -j MASQUERADE
log info "All rules cleared"


