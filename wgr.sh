#!/bin/bash

read_bool() {
    local OPT="$(jq -r ".${1,,}" <<< "$WGR_CONFIG_DATA")"
    [ "${OPT,,}" = "true" ]
}

read_string() {
    jq -r ".${1,,}" <<< "$WGR_CONFIG_DATA"
}

ask() {
    read -re -i "$2" -p "$1: " ans
    echo "$ans"
}

yes_no() {
    read -re -i "$2" -p "$1: " -n 1 ans
    [ "${ans,,}" = "y" ]
}

explode_network() {
    local lo hi a b c d e f g h
    lo=$(ipcalc -n "$1" | awk '/HostMin/ { print $2 }')
    hi=$(ipcalc -n "$1" | awk '/HostMax/ { print $2 }')
    IFS=. read -r a b c d <<< $lo
    IFS=. read -r e f g h <<< $hi
    for ip in $(eval "echo {$a..$e}.{$b..$f}.{$c..$g}.{$d..$h}"); do echo $ip; done
}

get_free_ipv4() {
    local IPV4_NETWORK="$(read_string IPV4_NETWORK)" ALL_IPS="$(mktemp)" OCC_IPS="$(mktemp)"
    explode_network "$IPV4_NETWORK" > "$ALL_IPS"
    read_string SERVER_IP > "$OCC_IPS"
    jq -r '.[] | .ipv4' <<< "$CLIENTS_DB" >> "$OCC_IPS"
    comm -3 <(sort "$ALL_IPS") <(sort "$OCC_IPS") | sort -n -t. -k4 | head -n1
    rm "$ALL_IPS" "$OCC_IPS"
}

init_server() {
    local WG_CONF="$(read_string WG_CONFIG)"
    if [ -f "${WG_CONF:=wg0.conf}" ]
    then
        yes_no "Server configuration '$WG_CONF' is already exist, do you want to continue?" || exit 1
    fi
    local SERVER_PKEY="$(read_string SERVER_PKEY)"
    local SERVER_PUBKEY="$(read_string SERVER_PUBKEY)"
    local SERVER_PORT="$(read_string SERVER_PORT)"
    local SERVER_IP="$(read_string SERVER_IP)"
    echo '[Interface]' > "$WG_CONF"
    echo "ListenPort = ${SERVER_PORT:=15900}" >> "$WG_CONF"
    echo "Address = ${SERVER_IP:=10.1.0.1}" >> "$WG_CONF"
    echo "PrivateKey = ${SERVER_PKEY}" >> "$WG_CONF"
    echo "SaveConfig = false" >> "$WG_CONF"
    if read_bool ADD_POST_HOOKS
    then
        local POST_UP="$(read_string POST_UP_HOOK)" POST_DOWN="$(read_string POST_DOWN_HOOK)"
        echo "PostUp = ${POST_UP:=/etc/wireguard/post-up.sh} %i" >> "$WG_CONF"
        echo "PostDown = ${POST_DOWN:=/etc/wireguard/post-down.sh} %i" >> "$WG_CONF"
    fi
    echo >> "$WG_CONF"
    if [ $(jq -r 'length' <<< "$CLIENTS_DB") -gt 0 ]
    then
        yes_no "There already client database, do you want to regenerate it?" || return
    fi
    for client in "$(jq -c '.[]' <<< "$CLIENTS_DB")"
    do
        echo
    done
}

generate_client() {
    local DIR="$(mktemp -d)"
    local CLIENT="$1" METHOD="$2" TUNNEL_FILE="$DIR/$(read_string SERVER_NAME).conf"
    local PKEY="$(jq -r '.private_key' <<< "$CLIENT")" ADDR="$(jq -r '.ipv4' <<< "$CLIENT")" KEEPALIVE="$(jq -r '.keepalive' <<< "$CLIENT")" ALLOWED_IPS="$(jq -r '.allowed_ips' <<< "$CLIENT")"
    local SERVER_ENDPOINT="$(read_string SERVER_ENDPOINT)" SERVER_PORT="$(read_string SERVER_PORT)" SERVER_PUBKEY="$(read_string SERVER_PUBKEY)" PSK="$(jq -r '.psk' <<< "$CLIENT")" DNS="$(read_string DNS)"
    echo '[Interface]' > "$TUNNEL_FILE"
    echo "PrivateKey = $PKEY" >> "$TUNNEL_FILE"
    echo "Address = $ADDR" >> "$TUNNEL_FILE"
    [ -n "$DNS" ] && echo "DNS = $DNS" >> "$TUNNEL_FILE"
    echo >> "$TUNNEL_FILE"
    echo '[Peer]' >> "$TUNNEL_FILE"
    echo "PublicKey = $SERVER_PUBKEY" >> "$TUNNEL_FILE"
    [ -n "$PSK" ] && echo "PresharedKey = $PSK" >> "$TUNNEL_FILE"
    echo "Endpoint = $SERVER_ENDPOINT:${SERVER_PORT:-15900}" >> "$TUNNEL_FILE"
    echo "AllowedIPs = $ALLOWED_IPS" >> "$TUNNEL_FILE"
    [ -n "$KEEPALIVE" ] && echo "PersistentKeepalive = $KEEPALIVE" >> "$TUNNEL_FILE"
    echo >> "$TUNNEL_FILE"
    echo "$TUNNEL_FILE"
    if [ "${METHOD,,}" == "qr" ]
    then 
        qrencode -t utf8 < "$TUNNEL_FILE"
    else
        local ZIP_NAME="client_$(jq -r '.name' <<< "$CLIENT").zip"
        zip -j "$ZIP_NAME" "$TUNNEL_FILE"
        echo "Tunnel file packaged in $ZIP_NAME"
    fi
}

add_client() {
    local DT="$(date --iso-8601=seconds)"
    local ID="$(openssl rand -hex 3 | tr 'a-z' 'A-Z')"
    local NAME="$(ask "Enter client name" "$1")"
    local DESCRIPTION="$2"
    [ -z "$DESCRIPTION" ] && yes_no "Add description?" && DESCRIPTION="$(ask "Enter description")"
    local PKEY="$(wg genkey)"
    local PUBKEY="$(wg pubkey <<< "$PKEY")"
    read_bool "PSK_ENABLED" && local PSK="$(wg genpsk)"
    local IPV4="$(get_free_ipv4)"
    local ALLOWED_IPS="$(read_string IPV4_NETWORK)"
    yes_no "Add another networks to AllowedIPs?" && ALLOWED_IPS="$(ask "Enter networks in CIDR notation separated by colon")"
    yes_no "Set this tunnel as default gateway?" && ALLOWED_IPS="0.0.0.0/0, $ALLOWED_IPS"
    yes_no "Keep connection alive?" && local KEEPALIVE="$(ask "Enter keep alive interval" 25)"
    CLIENT_DOC="$(jq -c --arg id "$ID" --arg pkey "$PKEY" --arg pubkey "$PUBKEY" --arg name "$NAME" --arg descr "$DESCRIPTION" --arg psk "$PSK" --arg dt "$DT" --arg ipv4 "$IPV4" --arg allowed_ips "$ALLOWED_IPS" --arg ka_val "$KEEPALIVE" '.id = $id | .private_key = $pkey | .public_key = $pubkey | .name = $name | .description = $descr | .psk = $psk | .ipv4 = $ipv4 | .allowed_ips = $allowed_ips | .keepalive = $ka_val | .created = $dt' <<< "{}")"
    CLIENTS_DB="$(jq -c -M ". += [$CLIENT_DOC]" <<< "$CLIENTS_DB")"
    yes_no "Generate tunnel file?" && generate_client "$CLIENT_DOC" "$(yes_no "Generate QR code?" && echo qr || echo file)"
}


load_client() {
    local ID="$1"
    local CLIENT_DOC="$(jq -c --arg id "$ID" '.[] | select(.id == $id)' <<< "$CLIENTS_DB")"
    if [ -z "$CLIENT_DOC" ]
    then
        echo "Client with id $ID not found"
        exit 1
    else
        echo $CLIENT_DOC
    fi
}

cleanup() {
    [[ -n "$CLIENTS_DB" && -f "$CLIENTS_FILE" ]] && jq -M <<< "$CLIENTS_DB" > "$CLIENTS_FILE"
}

WGR_CONFIG="${WGR_CONFIG:-wgr_config.json}"
[ -f "$WGR_CONFIG" ] || { echo "WGR configuration file not found!"; exit 11; }
WGR_CONFIG_DATA="$(jq -c < "$WGR_CONFIG")"
CLIENTS_FILE="$(jq -r '.clients_file' <<< "$WGR_CONFIG_DATA")"
[ -f "$CLIENTS_FILE" ] || { echo "Client database not found!"; exit 12; }
CLIENTS_DB="$(jq -c < "$CLIENTS_FILE")"

trap 'rc=$?; cleanup; exit $rc' EXIT

case $# in
    0)
        echo "Usage:"
        echo
        echo "wgr [command] <options>"
        echo 
        echo "[command]:"
        echo 
        echo "add-client [name] [description]: Adds new client"
        echo -e "\tname - name of the client (will be normalized to regex [A-Za-z0-9_])"
        echo -e "\tdescription - optional description of the client"
        echo
    ;;
    *)
        COMMAND="$1"
        shift
        case "${COMMAND,,}" in
            "add-client")
                add_client $@
            ;;
            "gen-client-tun")
                load_client $@
            ;;
            *)
                echo "Not allowed command: $COMMAND"
                exit 1
            ;;
        esac
    ;;
esac

