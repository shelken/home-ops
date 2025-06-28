
要在OpenWrt 的LuCI 中开启RPC 功能，需要安装 luci-mod-rpc、luci-lib-ipkg 和 luci-compat 软件包，然后重启uhttpd 服务
```shell
opkg install luci-mod-rpc luci-lib-ipkg luci-compat
/etc/init.d/uhttpd restart
```
