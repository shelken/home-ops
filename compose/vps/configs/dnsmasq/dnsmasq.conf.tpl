port=5353
listen-address=0.0.0.0
bind-interfaces
no-resolv
strict-order

# 内部域与主域都交集群 k8s-gateway；更具体的内部域规则优先
server=/int.{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/192.168.69.41
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/192.168.69.41

# gateway 不可用时的顺序回落；公网上游使用 1.1.1.1 / 8.8.8.8
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/1.1.1.1
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/8.8.8.8
server=1.1.1.1
server=8.8.8.8
