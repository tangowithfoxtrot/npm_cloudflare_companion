#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck source=./logger.sh
source ./src/logger.sh

run() { # TODO: move this to a common file
  cmd="$1"
  result="$(eval "$(echo "$cmd" | tr '\n' ' ')")"
  echo "$result"
}

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
  cmd="curl -sX 'GET' \\
          \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H \"Authorization: Bearer $TOKEN\" | jq -r '.[].domain_names | .[]'"

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "getting proxy host names with the following cURL command:

      $cmd"

  response="$(run "$cmd")"
  echo "$response"

  [[ -n "${DEBUG:-}" ]] && log_debug "npm.get_proxy_host_names response:\n\n$response"
}

npm.get_proxy_hosts() {
  endpoint="nginx/proxy-hosts"
  cmd="curl -sX 'GET' \\
          \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H \"Authorization: Bearer $TOKEN\" | jq"

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "getting proxy hosts with the following cURL command:

      $cmd"

  response="$(run "$cmd")"
  echo "$response"
}

npm.create_proxy_hosts() {
  endpoint="nginx/proxy-hosts"
  proxy_hosts="$1"

  for proxy_host in $(echo "$proxy_hosts" | jq -c '.[]'); do
    cmd="curl -sX 'POST' \"$host/$endpoint\" \\
              -H 'Accept: application/json' \\
              -H 'Content-Type: application/json' \\
              -H \"Authorization: Bearer $TOKEN\" \\
              -d '$proxy_host' | jq"

    [[ -n "${DEBUG:-}" ]] &&
      log_debug "creating host $(echo "$proxy_host" | jq -r '.domain_names | .[]') with the following cURL command:

        $cmd"

    response="$(run "$cmd")"

    if [[ ! "$(echo "$response" | jq -r .error)" == "null" ]]; then
      log_bold_error "error creating proxy host $(echo "$proxy_host" | jq -r '.domain_names | .[]')"
      log_verbose "response: $response"
      echo "1"
    fi
  done
}

npm.update_proxy_host() {
  # the same as create_proxy_hosts, but with PUT instead of POST
  endpoint="nginx/proxy-hosts/$1"

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "updating proxy host $1 with the following cURL command:

      curl -sX 'PUT' \"$host/$endpoint\" \\
        -H 'Accept: application/json' \\
        -H 'Content-Type: application/json' \\
        -H \"Authorization: Bearer $TOKEN\" \\
        -d '$(echo "$2" | jq -c '.[]')' | jq"

  curl -sX 'PUT' \
    "$host/$endpoint" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d "$(echo "$2" | jq -c '.[]')" | jq >/dev/null
}

npm.delete_proxy_host() {
  # input: proxy_host_id
  endpoint="nginx/proxy-hosts/$1"
  cmd="curl -sX 'DELETE' \"$host/$endpoint\" -H 'Accept: application/json' -H \"Authorization: Bearer $TOKEN\""

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "deleting proxy host $1 with the following cURL command:

      $cmd | jq"

  response="$(eval "$cmd" | jq)"

  echo "$response"
}

npm.request_token() {
  endpoint="tokens"
  cmd="curl -sX 'POST' \\
          \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H 'Content-Type: application/json' \\
          -d '{\"identity\":\"$1\",\"scope\":\"$2\",\"secret\":\"$3\"}' \\
          | jq -r .token"

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "creating token for $1 with the following cURL command:
      
        $cmd"

  response="$(run "$cmd")"

  if [[ ! "$response" =~ ^ey ]]; then
    log_bold_error "error requesting token"
    log_verbose "token response: $response"
    exit 1
  fi

  echo "$response"
}

npm.refresh_token() {
  endpoint="tokens"
  cmd="curl -sX 'GET' \\
          \"$host/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H 'Content-Type: application/json' \\
          -H 'Authorization: Bearer $1' \\
          | jq -r .token"

  [[ -n "${DEBUG:-}" ]] &&
    log_debug "refreshing token with the following cURL command:

      $cmd"

  response="$(run "$cmd")"
  echo "$response"
}

npm.imperative_create() {
  mapfile -t existing_hosts < <(npm.get_proxy_host_names)
  mapfile -t hosts_in_config < <(npm.parse_proxy_hosts | jq -r '.[].domain_names | .[]')

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
  name="$2"  # proxy_host name to lookup

  echo "$input" | jq -r --arg name "$name" '.[] | select(.domain_names[0] == $name) | .id'
}

npm.reconcile_hosts() { # checks the state of existing proxy_hosts and creates, edits, or deletes them if they do not match
  mapfile -t existing_hosts < <(npm.get_proxy_host_names)
  mapfile -t hosts_in_config < <(npm.parse_proxy_hosts | jq -r '.[].domain_names | .[]')

  [[ -n "${DEBUG:-}" ]] && log_debug "existing_hosts:\n\n${existing_hosts[*]}"
  [[ -n "${DEBUG:-}" ]] && log_debug "hosts_in_config:\n\n${hosts_in_config[*]}"

  if [[ " ${existing_hosts[*]} " =~ ${hosts_in_config[*]} ]]; then
    log_success "proxy hosts are up-to-date"
    return
  fi

  local hosts="$HOSTS"

  # if any hosts_in_config are not in existing_hosts, create them
  for host_in_config in "${hosts_in_config[@]}"; do
    if [[ ! "${existing_hosts[*]}" =~ ${host_in_config} ]]; then
      proxy_host_requests="$(npm.parse_proxy_hosts | jq -c --arg host "${host_in_config}" '.[] | select(.domain_names | contains([$host])) | [.]')"

      result="$(npm.create_proxy_hosts "$proxy_host_requests")"
      if [[ "$result" == "1" ]]; then
        log_error "error creating $host_in_config"
      else
        log_success "created $host_in_config"
      fi
    fi
  done

  # NOT IMPLEMENTING THIS YET; it doesn't work anyway
  # # if any hosts in existing_hosts are not in hosts_in_config, delete them
  # for existing_host in "${existing_hosts[@]}"; do
  #   if [[ ! " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
  #     proxy_host_id="$(npm.lookup_proxy_host_by_name "$hosts" "$existing_host")"
  #     if [[ -n "${DEBUG:-}" ]]
  #     then
  #       npm.delete_proxy_host "$proxy_host_id" >&2
  #     else
  #       npm.delete_proxy_host "$proxy_host_id" >/dev/null && \
  #       log_success "deleted $existing_host 🗑️"
  #     fi
  #   fi
  # done

  for existing_host in "${existing_hosts[@]}"; do
    # TODO: add state so that if the host is already up-to-date, we don't update it
    if [[ " ${hosts_in_config[*]} " =~ ${existing_host} ]]; then
      proxy_host_id="$(npm.lookup_proxy_host_by_name "$hosts" "$existing_host")"
      proxy_host_request="$(npm.parse_proxy_hosts | jq -c --arg host "${existing_host}" '.[] | select(.domain_names | contains([$host])) | [.]')"
      if [[ -n "${DEBUG:-}" ]]; then
        npm.update_proxy_host "$proxy_host_id" "$proxy_host_request" >&2
      else
        npm.update_proxy_host "$proxy_host_id" "$proxy_host_request" >/dev/null &&
          log_success "updated $existing_host"
      fi
    fi
  done
}

main() {
  # shellcheck disable=SC2155,SC2154
  export TOKEN="$(npm.request_token "$username" "" "$password")"
  # shellcheck disable=SC2155
  export HOSTS="$(npm.get_proxy_hosts)"
  npm.reconcile_hosts
}

# main "$@"
