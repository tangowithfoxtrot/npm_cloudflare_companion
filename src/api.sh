#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

config_file="${1:-config.yml}"
host="$(yq eval '.host' "$config_file")"
username="$(yq eval '.username' "$config_file")"
password="$(yq eval '.password' "$config_file")"

npm.parse_proxy_hosts() {
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

npm.get_proxy_host_names() {
  endpoint="nginx/proxy-hosts"

  [[ -n "${DEBUG:-}" ]] && \
    echo "getting proxy hosts with the following cURL command:" >&2 && \
    echo "
      curl -sX 'GET' \\
      \"$host/$endpoint\" \\
      -H 'Accept: application/json' \\
      -H \"Authorization: Bearer $TOKEN\" | jq -r .[].domain_names.[]" >&2 && \
    echo >&2

  curl -sX 'GET' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq -r .[].domain_names.[]
}


npm.get_proxy_hosts() {
  endpoint="nginx/proxy-hosts"

  [[ -n "${DEBUG:-}" ]] && \
    echo "getting proxy hosts with the following cURL command:" >&2 && \
    echo "
      curl -sX 'GET' \\
      \"$host/$endpoint\" \\
      -H 'Accept: application/json' \\
      -H \"Authorization: Bearer $TOKEN\" | jq -r .[].domain_names.[]" >&2 && \
    echo >&2

  curl -sX 'GET' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq
}

npm.create_proxy_hosts() {
  endpoint="nginx/proxy-hosts"
  proxy_hosts="$1"

  for proxy_host in $(echo "$proxy_hosts" | jq -c '.[]'); do
    [[ -n "${DEBUG:-}" ]] && \
      echo "creating host $(echo "$proxy_host" | jq -r .domain_names.[]) with the following cURL command:" >&2 && \
      echo "
        curl -sX 'POST' \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H 'Content-Type: application/json' \\
          -H \"Authorization: Bearer $TOKEN\" \\
          -d '$proxy_host' | jq" >&2 && \
      echo >&2

    # Send the API request for the current proxy_host
    curl -sX 'POST' \
      "$host/$endpoint" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -d "$proxy_host" | jq
  done
}

npm.update_proxy_host() {
  # the same as create_proxy_hosts, but with PUT instead of POST
  endpoint="nginx/proxy-hosts/$1"

  [[ -n "${DEBUG:-}" ]] && \
    echo "updating proxy host $1 with the following cURL command:" >&2 && \
    echo "
      curl -sX 'PUT' \"$host/$endpoint\" \\
        -H 'Accept: application/json' \\
        -H 'Content-Type: application/json' \\
        -H \"Authorization: Bearer $TOKEN\" \\
        -d '$2' | jq" >&2 && \
    echo >&2

  curl -sX 'PUT' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d "$2" | jq
}

npm.delete_proxy_host() {
  # input: proxy_host_id
  endpoint="nginx/proxy-hosts/$1"

  [[ -n "${DEBUG:-}" ]] && \
    echo "deleting proxy host $1 with the following cURL command:" >&2 && \
    echo "
      curl -sX 'DELETE' \"$host/$endpoint\" \\
        -H 'Accept: application/json' \\
        -H \"Authorization: Bearer $TOKEN\" | jq" >&2 && \
    echo >&2

  curl -sX 'DELETE' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq
}

npm.request_token() {
  endpoint="tokens"

    [[ -n "${DEBUG:-}" ]] && \
      echo "creating token for $1 with the following cURL command:" >&2 && \
      echo "
        curl -sX 'POST' \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H 'Content-Type: application/json' \\
          -d '{\"identity\":\"$1\",\"scope\":\"$2\",\"secret\":\"$3\"}' | jq -r .token" >&2 && \
      echo >&2

  curl -sX 'POST' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":\"$1\",\"scope\":\"$2\",\"secret\":\"$3\"}" | jq -r .token \
      || echo "error requesting token"
}

npm.refresh_token() {
  endpoint="tokens"

  [[ -n "${DEBUG:-}" ]] && \
    echo "refreshing token with the following cURL command:" >&2 && \
    echo "
      curl -sX 'GET' \\
      \"$host/$endpoint\" \\
      -H 'Accept: application/json' \\
      -H \"Authorization: Bearer $TOKEN\" | jq -r .token" >&2 && \
    echo >&2

  curl -sX 'GET' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $TOKEN" | jq -r .token
}

npm.imperative_create() {
  mapfile -t existing_hosts < <(npm.get_proxy_host_names)
  mapfile -t hosts_in_config < <(npm.parse_proxy_hosts | jq -r .[].domain_names.[])

  # if any hosts_in_config are not in existing_hosts, create them
  for host_in_config in "${hosts_in_config[@]}"; do
    if [[ ! " ${existing_hosts[*]} " =~ ${host_in_config} ]]; then
      proxy_host_requests="$(npm.parse_proxy_hosts | jq -c --arg host "${host_in_config}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      npm.create_proxy_hosts "$proxy_host_requests"
    fi
  done
}

npm.lookup_proxy_host_by_name() {
  input="$1" # proxy_hosts JSON
  name="$2" # proxy_host name to lookup

  echo "$input" | jq -r --arg name "$name" '.[] | select(.domain_names[0] == $name) | .id'
}

npm.reconcile_hosts() { # checks the state of existing proxy_hosts and creates, edits, or deletes them if they do not match
  mapfile -t existing_hosts < <(npm.get_proxy_host_names)
  mapfile -t hosts_in_config < <(npm.parse_proxy_hosts | jq -r .[].domain_names.[])
  local hosts="$HOSTS"

  # if any hosts_in_config are not in existing_hosts, create them
  for host_in_config in "${hosts_in_config[@]}"; do
    if [[ ! " ${existing_hosts[*]} " =~ ${host_in_config} ]]; then
      proxy_host_requests="$(npm.parse_proxy_hosts | jq -c --arg host "${host_in_config}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      if [[ -n "${DEBUG:-}" ]]
      then
        npm.create_proxy_hosts "$proxy_host_requests" >&2
      else
        npm.create_proxy_hosts "$proxy_host_requests" >/dev/null && \
        echo "created $host_in_config"
      fi
    fi
  done

  # if any hosts in existing_hosts are not in hosts_in_config, delete them
  for existing_host in "${existing_hosts[@]}"; do
    if [[ ! " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
      proxy_host_id="$(npm.lookup_proxy_host_by_name "$hosts" "$existing_host")"
      if [[ -n "${DEBUG:-}" ]]
      then
        npm.delete_proxy_host "$proxy_host_id" >&2
      else
        npm.delete_proxy_host "$proxy_host_id" >/dev/null && \
        echo "deleted $existing_host"
      fi
    fi
  done

  for existing_host in "${existing_hosts[@]}"; do
    if [[ " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
      proxy_host_id="$(npm.lookup_proxy_host_by_name "$hosts" "$existing_host")"
      proxy_host_request="$(npm.parse_proxy_hosts | jq -c --arg host "${existing_host}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      if [[ -n "${DEBUG:-}" ]]
      then
        npm.update_proxy_host "$proxy_host_id" "$proxy_host_request" >&2
      else
        npm.update_proxy_host "$proxy_host_id" "$proxy_host_request" >/dev/null && \
        echo "updated $existing_host"
      fi
    fi
  done
}

main() {
  # shellcheck disable=SC2155
  export TOKEN="$(npm.request_token "$username" "" "$password")"
  # shellcheck disable=SC2155
  export HOSTS="$(npm.get_proxy_hosts)"
  npm.reconcile_hosts
}

main "$@"
