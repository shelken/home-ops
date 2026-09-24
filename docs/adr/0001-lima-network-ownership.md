# Lima 节点的 netplan 归 Lima 管，Ansible 只做 DNS 与 VLAN

Lima 节点的接口命名、寻址与 `route-metric` 由 Lima 经 cloud-init 下发，`setup-network.yaml` 对它们只写 DNS drop-in 与 VLAN；PVE 节点的分支不变。原因是 cloud-init 的 `50-cloud-init.yaml` 同时承载接口命名（`match` + `set-name`）与 metric，Ansible 另写一份 `50-node-network.yaml` 既重复，又要求它自己生成 `.link` 才能让模板按 `eth\d+` 枚举到接口——那份文件一旦被删，两个网口会同时失去 DHCP。改 Lima 节点的 LAN 配置应改 `lima/<host>.yaml` 的 `networks[]`。
