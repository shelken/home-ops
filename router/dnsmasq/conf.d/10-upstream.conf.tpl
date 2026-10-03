# 家庭 LAN 的 DNS 分流，由 .taskfile 下发为 /etc/dnsmasq.d/10-upstream.conf
# 本地 hosts 与自举记录优先于本文件的转发规则；此处只决定「查不到时问谁」。

# 按声明顺序查询，前一个无响应才用下一个；避免公网答案与内网答案竞速
strict-order

# 主域与内部域都交集群里的 k8s-gateway，由它按当前集群资源应答
server=/${MAIN_DOMAIN}/${DNS_GATEWAY}
server=/${INTERNAL_DOMAIN}/${DNS_GATEWAY}

# gateway 不可用时的顺序回落；集群内没有的主域名由 gateway 自行解析公网
server=/${MAIN_DOMAIN}/${DNS_FALLBACK}
