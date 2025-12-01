## 查询

ubuntu

```shell
sudo cat /etc/netplan/xx.conf
```

## lima

在配置文件中限定，`dns:` 配置限定了默认的网卡。额外的卡，即在`networks:`配置下的卡目前没有看到可以调整的

## pve-vm

```shell
qm set $id --nameserver "223.5.5.5"
```
