#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source ./src/cf_api.sh
source ./src/npm_api.sh

config_file="${1:-config.yml}"

# Proxy config
host="$(yq eval '.host' "$config_file")"
ip_address_of_proxy_host="$(yq eval '.ip_address' "$config_file")"
username="$(yq eval '.username' "$config_file")"
password="$(yq eval '.password' "$config_file")"

# Cloudflare config
cloudflare_api="https://api.cloudflare.com/client/v4"
domain_name="$(yq eval '.domain_name' "$config_file")"
api_token="$(yq eval '.cf_api_token' "$config_file")"
proxy_hosts="$(yq eval '.proxy_hosts | to_entries | .[].key' "$config_file")"

main() {
  # shellcheck disable=SC2155
  export TOKEN="$(npm.request_token "$username" "" "$password")"
  # shellcheck disable=SC2155
  export HOSTS="$(npm.get_proxy_hosts)"
  
  clear

  log_info "adding proxy hosts to nginx..."
  npm.reconcile_hosts
  echo

  # shellcheck disable=SC2155
  export ZONE_ID="$(cf.get_zone_id)"
  # shellcheck disable=SC2155
  export DOMAINS_KV_PAIR="$(cf.make_domain_id_name_key_pair "$(cf.list_dns_records)")"

  # re-source the config file because npm.reconcile_hosts modifies the proxy_hosts var
  proxy_hosts="$(yq eval '.proxy_hosts | to_entries | .[].key' "$config_file")"
  log_info "adding proxy hosts DNS entries to Cloudflare..."
  cf.reconcile_proxy_hosts
}

main "$@"
