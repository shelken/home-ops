## 网络切换变更简述(由tunnel转为公网直连)

> [关联commit](https://github.com/shelken/home-ops/commit/da75f2ea67d52034d731ab5388da09c3adeb7c04)

### 移除 cloudflare-tunnel

关闭了 `homelab-external -> ${CLOUDFLARE_TUNNEL_ID}.cfargotunnel.com` dnsendpoint

```yaml
spec:
  endpoints:
    - dnsName: homelab-external.${MAIN_DOMAIN}
      recordType: CNAME
      targets:
        - ${CLOUDFLARE_TUNNEL_ID}.cfargotunnel.com
```

### 添加回 caddy-external (ddns + caddy)

v6 入口 + ddns

### 变更 cloudflare-dns

注释 cloudflare-proxied

```yaml
extraArgs:
  - --cloudflare-dns-records-per-page=1000
  # - --cloudflare-proxied
```

启用 `homelab-external -> homelab-dynamic` dnsendpoint

```yaml
spec:
  endpoints:
    - dnsName: "homelab-external.${MAIN_DOMAIN}"
      recordType: CNAME
      targets: ["homelab-dynamic.${MAIN_DOMAIN}"]
```

整体链路为 echo -> homelab-external -> homelab-dynamic(v4(手动)/v6(自动))
