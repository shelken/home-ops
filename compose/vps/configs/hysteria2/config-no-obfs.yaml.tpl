listen: :10358

tls:
  cert: /data/hysteria2/tls/wildcard_.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}.crt
  key: /data/hysteria2/tls/wildcard_.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}.key

auth:
  type: password
  password: azure://shelken-homelab/compose-vps/HYSTERIA2_AUTH_PASSWORD

bandwidth:
  up: 160 mbps
  down: 160 mbps

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
