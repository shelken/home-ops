# kube-prometheus-stack

## 外部节点部署

VPS 的 node-exporter 由 nix-config 的 `hosts/vps/vps-cc/apps/node-exporter.nix` 声明（NixOS 的 oci-containers）运行，抓取目标配置在 [`app/scrapeconfig.yaml`](./app/scrapeconfig.yaml)
