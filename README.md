# Nginx Proxy Manager Cloudflare Companion
Nginx Proxy Manager companion that manages proxy hosts and their associated DNS entries

## Example config file
`config.yml`
```yaml
host: "https://nginx-proxy-manager.example.com/api"
username: "api_user@example.com"
password: "password" # be careful
cf_api_token: "cf_api_token" # be careful
domain_name: "your_domain.whatever" # be careful

proxy_hosts:
  webserver.example.com:
    forward_scheme: "http"
    forward_host: "webserver"
    forward_port: 8080
    block_exploits: true
    access_list_id: '0'
    certificate_id: 3
    ssl_forced: true
    http2_support: true
    meta:
      letsencrypt_agree: false
      dns_challenge: false
    advanced_config: ''
    locations: []
    caching_enabled: false
    allow_websocket_upgrade: true
    hsts_enabled: true
    hsts_subdomains: false
  git.example.com:
    forward_scheme: "http"
    forward_host: "172.0.0.3"
    forward_port: 3000
    block_exploits: true
    access_list_id: '0'
    certificate_id: 3
    ssl_forced: true
    http2_support: true
    meta:
      letsencrypt_agree: false
      dns_challenge: false
    advanced_config: ''
    locations: []
    caching_enabled: false
    allow_websocket_upgrade: true
    hsts_enabled: true
    hsts_subdomains: false
```
