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
which curl > /dev/null || { echo "curl not found"; exit 1; }
which jq > /dev/null || { echo "jq not found"; exit 1; }
which ipcalc > /dev/null || { echo "ipcalc not found"; exit 1; }

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%SZ%z') - regional-routing - ${1^^} - $2" | tee -a "regional-routing.log"
}

RIPE_URL='https://stat.ripe.net/data/country-resource-list/data.json?resource=ru'
[ -z "$USER_LIST" ] && USER_LIST="user_subnet_list.conf"
IP_TMP="$(mktemp "/tmp/ip_data_XXXXXXXXX.json")"
PROCESSED="$(mktemp "/tmp/processed_ip_addrs_XXXXXXX.json")"
INTERNAL_GATEWAY="$(ip -j route | jq -r '.[] | select(.dst == "default") | .gateway')"
IFACE="$(ip -j route | jq -r '.[] | select(.dst == "default") | .dev')"

[ -z "$INTERNAL_GATEWAY" ] && { log error "Unable to retrieve default gateway IP"; exit 2; }
[ -z "$IFACE" ] && { log error "Unable to retrieve default gateway iface"; exit 2; }

log info "Downloading russian subnet list from RIPE"
curl --request GET -sL \
     --url "$RIPE_URL"\
     --output "$IP_TMP"

log info "Deaggerating subnets"
for subnet in $(jq -r '.data.resources.ipv4[]' < "$IP_TMP")
do
  if grep -q '-' <<< "$subnet"
  then
    ipcalc $subnet | grep -v 'deaggregate' >> "$PROCESSED"
  else
    echo $subnet >> "$PROCESSED"
  fi
done

if [ -f "$USER_LIST" ]
then
  log info "Adding user-defined route list"
  grep -v '#' < "$USER_LIST" >> "$PROCESSED"
fi

TOTAL_ROUTES="$(wc -l < "$PROCESSED")"
ROUTES_ADDED=0

log info "Flushing route table (ifdown $IFACE && ifup $IFACE)"
ifdown $IFACE > /dev/null 2>&1
ifup $IFACE > /dev/null 2>&1

log info "Populating route table"
while read subnet
do
  ip route add $subnet via $INTERNAL_GATEWAY dev $IFACE && ROUTES_ADDED=$(( $ROUTES_ADDED + 1 ))
done < "$PROCESSED"

log info "Populated $ROUTES_ADDED of $TOTAL_ROUTES routes"


