## Compose 规则

先看 `.taskfile/compose.yaml`：

```text
sync: .env.tpl + *.tpl -> 渲染产物 -> rsync -> 清理本地产物
deploy: sync -> docker compose pull -> docker compose up -d --remove-orphans
```

规则：

- 需要 Azure KeyVault 注入才写 `.tpl`。
- 普通文件不渲染，渲染产物不提交。
- **配置更新生效（Tip）**：Docker Compose 默认只在服务定义（镜像、环境变量、端口）变化时重建容器。若仅修改了 `configs:` 挂载引用的配置文件（如 `Caddyfile`），默认执行部署时容器保持原样运行，不会自动加载新配置；必须传参强制重建（如 `task compose:deploy:vps -- --force-recreate`），或通过服务原生方式手动热重载（如 `ssh vps-cc "docker exec caddy caddy reload --config /etc/caddy/Caddyfile"`）。
