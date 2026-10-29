# kube-prometheus-stack

## 外部节点部署

在外部主机（如 VPS）运行的 node-exporter 配置示例（镜像版本与配置定义以 [`compose/vps/docker-compose.yml`](../../../../../compose/vps/docker-compose.yml) 为准）：

### node-exporter
```yaml
services:
  node-exporter:
    command:
      - '--path.rootfs=/host/root'
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.udev.data=/host/root/run/udev/data'
      - '--web.listen-address=0.0.0.0:9100'
      - >-
        --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
    image: prom/node-exporter:${NODE_EXPORTER_VERSION:-latest}
    networks:
      - homelab
    ports:
      - '${DEPLOY_HOST}:9100:9100/tcp'
    restart: always
    volumes:
      - /:/host/root:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
```
