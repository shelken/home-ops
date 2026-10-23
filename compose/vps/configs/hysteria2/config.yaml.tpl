listen: :10357

tls:
  cert: /data/hysteria2/tls/wildcard_.{{bws://compose-vps/MAIN_DOMAIN}}.crt
  key: /data/hysteria2/tls/wildcard_.{{bws://compose-vps/MAIN_DOMAIN}}.key

obfs:
  type: salamander
  salamander:
    password: bws://compose-vps/HYSTERIA2_OBFS_PASSWORD

auth:
  type: password
  password: bws://compose-vps/HYSTERIA2_AUTH_PASSWORD

bandwidth:
  up: 160 mbps
  down: 160 mbps

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
