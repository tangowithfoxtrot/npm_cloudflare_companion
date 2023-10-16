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
    -H "Authorization: Bearer $TOKEN" | jq -r .[].domain_names.[]
}

create_proxy_hosts() {
  endpoint="nginx/proxy-hosts"
  proxy_hosts="$1"

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

imperative_create() {
  mapfile -t existing_hosts < <(get_proxy_hosts)
  mapfile -t hosts_in_config < <(parse_proxy_hosts | jq -r .[].domain_names.[])

  # if any hosts_in_config are not in existing_hosts, create them
  for host_in_config in "${hosts_in_config[@]}"; do
    if [[ ! " ${existing_hosts[*]} " =~ ${host_in_config} ]]; then
      proxy_host_requests="$(parse_proxy_hosts | jq -c --arg host "${host_in_config}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      create_proxy_hosts "$proxy_host_requests"
    fi
  done
}

reconcile_hosts() { # checks the state of existing proxy_hosts and creates, edits, or deletes them if they do not match
  mapfile -t existing_hosts < <(get_proxy_hosts)
  mapfile -t hosts_in_config < <(parse_proxy_hosts | jq -r .[].domain_names.[])

  # if any hosts_in_config are not in existing_hosts, create them
  for host_in_config in "${hosts_in_config[@]}"; do
    if [[ ! " ${existing_hosts[*]} " =~ ${host_in_config} ]]; then
      proxy_host_requests="$(parse_proxy_hosts | jq -c --arg host "${host_in_config}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      create_proxy_hosts "$proxy_host_requests"
    fi
  done

  # if any existing_hosts are not in hosts_in_config, delete them
  for existing_host in "${existing_hosts[@]}"; do
    if [[ ! " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
      echo "delete $existing_host"
    fi
  done

  # if any existing_hosts are in hosts_in_config, check if they need to be updated
  for existing_host in "${existing_hosts[@]}"; do
    if [[ " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
      echo "update $existing_host"
    fi
  done
}


# shellcheck disable=SC2155
export TOKEN="$(request_token "$username" "" "$password")"
# imperative_create
# reconcile_hosts
