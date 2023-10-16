#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

config_file="${1:-config.yml}"
host="$(yq eval '.host' "$config_file")"
username="$(yq eval '.username' "$config_file")"
password="$(yq eval '.password' "$config_file")"

parse_proxy_hosts() {
  # transform the domain_names into an array
  yq eval '.proxy_hosts | select(. != null) | to_entries | [
    .[] | {
      "domain_names": [.key],
      "forward_scheme": .value.forward_scheme,
      "forward_host": .value.forward_host,
      "forward_port": .value.forward_port,
      "block_exploits": .value.block_exploits,
      "access_list_id": .value.access_list_id,
      "certificate_id": .value.certificate_id,
      "ssl_forced": .value.ssl_forced,
      "http2_support": .value.http2_support,
      "meta": {
        "letsencrypt_agree": .value.meta.letsencrypt_agree,
        "dns_challenge": .value.meta.dns_challenge
      },
      "advanced_config": .value.advanced_config,
      "locations": .value.locations,
      "caching_enabled": .value.caching_enabled,
      "allow_websocket_upgrade": .value.allow_websocket_upgrade,
      "hsts_enabled": .value.hsts_enabled,
      "hsts_subdomains": .value.hsts_subdomains
    }
  ]' "$config_file" -o json
}

get_proxy_hosts() {
  endpoint="nginx/proxy-hosts"

  curl -sX 'GET' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq .[].domain_names | jq -r .[]
}

create_proxy_hosts() {
  endpoint="nginx/proxy-hosts"
  proxy_hosts="$(parse_proxy_hosts)"

  for proxy_host in $(echo "$proxy_hosts" | jq -c '.[]'); do
    # Send the API request for the current proxy_host
    curl -sX 'POST' \
      "$host/$endpoint" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$proxy_host" | jq
  done
}

request_token() {
  endpoint="tokens"

  curl -sX 'POST' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":\"$1\",\"scope\":\"$2\",\"secret\":\"$3\"}" | jq -r .token
}

refresh_token() {
  endpoint="tokens"

  curl -sX 'GET' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq -r .token
}

# shellcheck disable=SC2155
export TOKEN="$(request_token "$username" "" "$password")"
create_proxy_hosts
