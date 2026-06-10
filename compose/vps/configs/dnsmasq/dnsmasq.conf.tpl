port=5353
listen-address=0.0.0.0
bind-interfaces
no-resolv
strict-order

server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/192.168.69.41
server=/{{azure://shelken-homelab/compose-vps/MAIN_DOMAIN}}/1.1.1.1
server=8.8.8.8
server=1.1.1.1
