# home-ops 管理的 DNS 分流，下发到专用 conf-dir
# 本地 hosts 与自举记录优先，未命中时由 k8s-gateway 按集群资源应答

server=/${MAIN_DOMAIN}/${DNS_GATEWAY}
server=/${INTERNAL_DOMAIN}/${DNS_GATEWAY}
