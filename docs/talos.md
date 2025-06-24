```shell

nix shell nixpkgs#talosctl

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out

talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.10.3

curl https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.10.3/metal-amd64.iso \
    -o _out/metal-amd64.iso

talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml
talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml

```

添加新的worker

```shell
qm clone 1003 116 --name talos-2

talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml
```

