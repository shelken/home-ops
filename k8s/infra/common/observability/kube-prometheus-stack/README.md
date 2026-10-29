# kube-prometheus-stack

## 外部节点部署

VPS 的 node-exporter 由 [`compose/vps/docker-compose.yml`](../../../../../compose/vps/docker-compose.yml) 的 `node-exporter` 服务运行，抓取目标配置在 [`app/scrapeconfig.yaml`](./app/scrapeconfig.yaml)
