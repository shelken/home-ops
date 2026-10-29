# Talos 记录

```bash
# 需本机已安装 talosctl（本仓库 mise 未纳入）

# 镜像 Schematic ID 与版本按需通过 Talos Image Factory (https://factory.talos.dev) 生成
export TALOS_VERSION="<TALOS_VERSION>"
export TALOS_SCHEMATIC_ID="<TALOS_SCHEMATIC_ID>"

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out \
  --install-image factory.talos.dev/installer/${TALOS_SCHEMATIC_ID}:${TALOS_VERSION}

curl -L "https://factory.talos.dev/image/${TALOS_SCHEMATIC_ID}/${TALOS_VERSION}/metal-amd64.iso" \
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
