# home-ops 管理的 DNS 分流，下发到专用 conf-dir
# 自举记录由 30-bootstrap.conf 以 address= 本地权威应答（A 与 AAAA 均不转发）；
# 未命中的主域与内部域记录由 k8s-gateway 按集群资源应答

server=/${MAIN_DOMAIN}/${DNS_GATEWAY}
server=/${INTERNAL_DOMAIN}/${DNS_GATEWAY}
