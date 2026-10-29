# Talos 记录

```bash
# 需本机已安装 talosctl（本仓库 mise 未纳入）

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.10.3

curl https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.10.3/metal-amd64.iso \
    -o _out/metal-amd64.iso

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml
talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml

```

## 扩容工作节点

克隆 PVE 虚拟机模板并下发 Worker 配置：

```bash
qm clone 1003 116 --name talos-2
talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml
```
