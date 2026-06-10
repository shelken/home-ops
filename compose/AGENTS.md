## Compose 规则

先看 `.taskfile/compose.yaml`：

```text
sync: .env.tpl + *.tpl -> 渲染产物 -> rsync -> 清理本地产物
deploy: sync -> docker compose pull -> docker compose up -d --remove-orphans
```

规则：

- 需要 Azure KeyVault 注入才写 `.tpl`。
- 普通文件不渲染，渲染产物不提交。
