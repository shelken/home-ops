# https://www.knot-dns.cz/docs/3.5/html/operation.html#example-2
server:
    rundir: /var/run/knot
    user: knot:knot
    listen: [127.0.0.1@5354, ${ROUTER_IP}@5354]
    udp-workers: 1
    tcp-workers: 1
    background-workers: 1

control:
    listen: /var/run/knot/knot.sock

# 默认 storage 位于 tmpfs，journal 必须放持久分区。
database:
    storage: /etc/knot/state
    journal-db-max-size: 24M

key:
  - id: external-dns.internal.
    algorithm: hmac-sha256
    secret: {{azure://${AZURE_VAULT}/internal-dns/TSIG_SECRET}}

# 仅私网监听，UPDATE/AXFR 必须验证 TSIG；不假设经过 SNAT 后的源地址。
acl:
  - id: external-dns
    key: external-dns.internal.
    action: [update, transfer]

# 主域 zone 内未匹配的名称转发公网递归；catch-nxdomain 让权威 NXDOMAIN 不遮蔽公网记录。
remote:
  - id: public-recursive
    address: ${DNS_UPSTREAM}

mod-dnsproxy:
  - id: main-fallback
    remote: public-recursive
    fallback: on
    catch-nxdomain: on

zone:
  - domain: ${MAIN_DOMAIN}
    storage: /etc/knot/state
    zonefile-sync: -1
    zonefile-load: none
    journal-content: all
    journal-max-usage: 16M
    acl: external-dns
    serial-policy: increment
    module: mod-dnsproxy/main-fallback
  - domain: ${INTERNAL_DOMAIN}
    storage: /etc/knot/state
    zonefile-sync: -1
    zonefile-load: none
    journal-content: all
    journal-max-usage: 16M
    acl: external-dns
    serial-policy: increment
