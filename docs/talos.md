```shell

nix shell nixpkgs#talosctl

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.10.3

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml

```

给 `controlplane`和`worker`配置env参数，下载镜像数据

```yaml
machine:
    env:
        https_proxy: http://192.168.6.248:7890
```

添加新的worker

```shell
qm clone 1003 116 --name talos-2

talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml
```

