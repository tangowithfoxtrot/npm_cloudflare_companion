# npm_cloudflare_companion
Nginx Proxy Manager Companion that manages proxy hosts and their associated DNS entries

## Example config file:
`config.yml`
```yaml
host: "https://nginx-proxy-manager.example.com/api"
username: "api_user@example.com"
password: "password" # be careful

proxy_hosts:
  webserver.example.com:
    forward_scheme: "http"
    forward_host: "webserver"
    forward_port: 8080
    block_exploits: true
    access_list_id: '0' # npm API expects this to be a string ¯\_(ツ)_/¯
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