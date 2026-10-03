port=5353
listen-address=0.0.0.0
bind-interfaces
no-resolv
strict-order

# 内部域与主域都交集群 k8s-gateway；更具体的内部域规则优先
server=/int.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/192.168.69.41
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/192.168.69.41

# gateway 不可用时的顺序回落；公网查询走 DoT，避免明文 53 被劫持或篡改
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/1.1.1.1@853#cloudflare-dns.com
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/8.8.8.8@853#dns.google
server=1.1.1.1@853#cloudflare-dns.com
server=8.8.8.8@853#dns.google
