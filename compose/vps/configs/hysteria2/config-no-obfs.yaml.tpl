listen: :10358

tls:
  cert: /data/hysteria2/tls/wildcard_.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}.crt
  key: /data/hysteria2/tls/wildcard_.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}.key

auth:
  type: password
  password: azure://shelken-homelab/compose-vps/HYSTERIA2_AUTH_PASSWORD

bandwidth:
  up: 100 mbps
  down: 100 mbps

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
