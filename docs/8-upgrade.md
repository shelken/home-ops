# 集群版本升级

## k3s

k3s 版本跟随 nix-config 的 nixpkgs：更新 nix-config 的 nixpkgs，先 deploy 控制面节点，再 deploy worker 节点。k3s 的 minor 版本写死在 nix-config 的 `k3s-node` 里，升 minor 要有意修改。细节见 nix-config 的 `hosts/k8s/README.md`

## 控制面参数变更

k3s 启动参数在 nix-config 的 `modules/features/homelab/k3s-node/` 维护。部署成功不证明守护进程能用新参数启动，涉及控制面启动参数的改动必须确认 k3s 实际重启并恢复；改动前先备好回滚点，并在有观察窗的时段执行，单控制面集群参数写错会让 API 直接中断
