# Homepage OpenWrt Widget 配置

## OpenWrt

参考上游文档：[Homepage OpenWrt Widget](https://gethomepage.dev/widgets/services/openwrt/#authorization)

在 `/usr/share/rpcd/acl.d/homepage.json` 添加 ACL 配置：

```json
{
  "homepage": {
    "description": "Homepage widget",
    "read": {
      "ubus": {
        "network.interface.wan": ["status"],
        "network.interface.lan": ["status"],
        "network.device": ["status"],
        "system": ["info"]
      }
    }
  }
}
```

在 `/etc/sysupgrade.conf` 添加备份保留项，避免固件升级丢失配置：

```bash
grep -qw homepage.json /etc/sysupgrade.conf || echo "/usr/share/rpcd/acl.d/homepage.json" >> /etc/sysupgrade.conf
```

在 `/etc/config/rpcd` 中配置只读账号：

```conf
config login
        option username 'homepage'
        option password '$1$<hash>'
        list read homepage
```
