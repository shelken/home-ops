#

## openwrt

> [文档](https://gethomepage.dev/widgets/services/openwrt/#authorization)

`/usr/share/rpcd/acl.d/` 添加 acl

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

防止升级不备份这个文件，给这个文件加上备份

```shell
grep -qw homepage.json /etc/sysupgrade.conf || echo "/usr/share/rpcd/acl.d/homepage.json" >> /etc/sysupgrade.conf
```

添加用户

`/etc/config/rpcd`

```conf
config login
        option username 'homepage'
        option password '$1$<hash>'
        list read homepage
```
