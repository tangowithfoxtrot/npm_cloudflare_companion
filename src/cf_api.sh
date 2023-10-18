#!/usr/bin/env bash
# A Cloudflare API script that updates the dns entries for the proxy_hosts in $config_file

set -euo pipefail
IFS=$'\n\t'

# shellcheck source=./logger.sh
source ./src/logger.sh

run() { # TODO: move this to a common file
  cmd="$1"
  result="$(eval "$(echo "$cmd" | tr '\n' ' ')")"
  echo "$result"
}

cf.get_zone_id() {
  endpoint="zones"
  cmd="curl -sX 'GET' \\
          \"$cloudflare_api/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H \"Authorization: Bearer $api_token\" | jq -r '.result[] | select(.name == \"$domain_name\") | .id'"

  [[ -n "${DEBUG:-}" ]] && \
    log_debug "getting zone ID with the following cURL command:

      $cmd"

  response="$(run "$cmd")"
  echo "$response"

  [[ -n "${DEBUG:-}" ]] && log_debug "cf.get_zone_id response: $response"
}

cf.list_dns_records() {
  endpoint="zones/$ZONE_ID/dns_records"
  cmd="curl -sX 'GET' \\
          \"$cloudflare_api/$endpoint\" \\
          -H 'Accept: application/json' \\
          -H \"Authorization: Bearer $api_token\" \\
          | yq -r '.result[] | (.name, .id)'"

  [[ -n "${DEBUG:-}" ]] && \
    log_debug "getting dns records with the following cURL command:

      $cmd"

  output="$(run "$cmd")"

  echo "$output"
  
    [[ -n "${DEBUG:-}" ]] && log_debug "cf.list_dns_records response:\n\n$output"
}

cf.make_domain_id_name_key_pair() {
  input="$1"
  domain_names=()
  ids=()

  # Read the input line by line
  while IFS= read -r line; do
    # If the line looks like a domain name, add it to the domain_names array
    if [[ $line == *"."* ]]; then
      domain_names+=("$line")
    # If the line looks like an id, add it to the ids array
    elif [[ $line =~ ^[0-9a-f]{32}$ ]]; then
      ids+=("$line")
    fi
  done <<<"$input"

  # Now pair each domain name with each id
  for i in "${!domain_names[@]}"; do
    echo "${domain_names[i]} ${ids[i]}"
  done
}

cf.domain_id_lookup() {
  domain_name="$1"
  output="$(echo "$DOMAINS_KV_PAIR" | grep -m 1 "^$domain_name" | awk '{print $2}')"
  echo "$output"
}

cf.domain_name_lookup() {
  domain_id="$1"
  echo "$DOMAINS_KV_PAIR" | grep -m 1 " $domain_id$" | awk '{print $1}'
}

cf.update_dns_record() {
  endpoint="zones/$ZONE_ID/dns_records/$3"
  name="$1"
  content="$2"
  type="A"
  ttl="1" # 1 = auto
  proxied="false"

  [[ -n "${DEBUG:-}" ]] && \
    log_debug "updating dns record with the following cURL command:

      curl -sX 'PUT' \\
        \"$cloudflare_api/$endpoint\" \\
        -H 'Accept: application/json' \\
        -H \"Authorization: Bearer $api_token\" \\
        -H 'Content-Type: application/json' \\
        -d \"{
          \\\"type\\\": \\\"$type\\\",
          \\\"name\\\": \\\"$name\\\",
          \\\"content\\\": \\\"$content\\\",
          \\\"ttl\\\": $ttl,
          \\\"proxied\\\": $proxied
        }\""

  is_success="$(curl -sX 'PUT' \
    "$cloudflare_api/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $api_token" \
    -H 'Content-Type: application/json' \
    -d "{
      \"type\": \"$type\",
      \"name\": \"$name\",
      \"content\": \"$content\",
      \"ttl\": $ttl,
      \"proxied\": $proxied
    }" | jq .success)"

  if [[ "$is_success" == "true" ]]; then
    log_success "updated dns record for $name"
  else
    log_error "failed to update dns record for $name" >&2
  fi
}

cf.create_dns_record() {
  endpoint="zones/$ZONE_ID/dns_records"
  name="$1"
  content="$ip_address_of_proxy_host"
  type="A"
  ttl="1" # 1 = auto
  proxied="false"

  [[ -n "${DEBUG:-}" ]] && \
    log_debug "creating dns record with the following cURL command:

      curl -sX 'POST' \\
        \"$cloudflare_api/$endpoint\" \\
        -H 'Accept: application/json' \\
        -H \"Authorization: Bearer $api_token\" \\
        -H 'Content-Type: application/json' \\
        -d \"{
          \\\"type\\\": \\\"$type\\\",
          \\\"name\\\": \\\"$name\\\",
          \\\"content\\\": \\\"$content\\\",
          \\\"ttl\\\": $ttl,
          \\\"proxied\\\": $proxied
        }\""

  is_success="$(curl -sX 'POST' \
    "$cloudflare_api/$endpoint" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $api_token" \
    -H 'Content-Type: application/json' \
    -d "{
      \"type\": \"$type\",
      \"name\": \"$name\",
      \"content\": \"$content\",
      \"ttl\": $ttl,
      \"proxied\": $proxied
    }" | jq .success)"

  if [[ "$is_success" == "true" ]]; then
    if [[ -n "${DEBUG:-}" ]]; then
      log_debug "created dns record for $name"
    else
      log_success "created dns record for $name"
    fi
  else
    log_error "failed to create dns record for $name" >&2
  fi

  echo "$is_success" >/dev/null
}

cf.lookup_proxy_host_domain_id() {
  proxy_host="$1"
  echo "$DOMAINS_KV_PAIR" | grep -m 1 "^$proxy_host" | awk '{print $2}' || true
}

cf.reconcile_proxy_hosts() {
  proxy_host_ids=()

  # Get the list of dns records from Cloudflare
  dns_records="$(cf.list_dns_records)"
  # TODO: remove the above redundant API call by transforming $DOMAINS_KV_PAIR
  # mapfile -t dns_records < <(echo "$DOMAINS_KV_PAIR" | awk '{print $1}')
  log_debug "dns_records:\n\n${dns_records[*]}"

  for proxy_host in $proxy_hosts; do
    proxy_host_id="$(cf.lookup_proxy_host_domain_id "$proxy_host")"
    proxy_host_ids+=("$proxy_host_id")

    if [[ ! " ${dns_records[*]} " =~ $proxy_host ]]; then
      cf.create_dns_record "$proxy_host"
    elif [[ ! " ${dns_records[*]} " =~ $proxy_host_id ]]; then
      dns_record_id="$(cf.domain_id_lookup "$proxy_host")"
      cf.update_dns_record "$proxy_host" "$ip_address_of_proxy_host" "$dns_record_id"
    else
      if [[ -n "${DEBUG:-}" ]]; then
        log_debug "dns record is up-to-date for $proxy_host"
      else
        log_success "dns record is up-to-date for $proxy_host"
      fi
    fi
  done
}

main() {
  # shellcheck disable=SC2155
  export ZONE_ID="$(cf.get_zone_id)"
  # shellcheck disable=SC2155
  export DOMAINS_KV_PAIR="$(cf.make_domain_id_name_key_pair "$(cf.list_dns_records)")"
  cf.reconcile_proxy_hosts
}

# main "$@"
