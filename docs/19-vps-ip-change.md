# VPS IP 变更

## Checklist

- [ ] MAIN_VPS_IP
- [ ] dnscontrol
- [ ] loon/clash/quan 订阅链接/代理节点/代理配置
- [ ] router passwall rule
- [ ] ssh config
- [ ] tailscale derp config

## Notes

- cloudcone 选择auto迁移ip时 同时存在两个ip udp 不正常; 暂时执行`ip addr del [old_ip]/[old_mask] dev eth0`恢复正常
