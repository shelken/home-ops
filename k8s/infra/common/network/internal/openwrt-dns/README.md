
要在OpenWrt 的LuCI 中开启RPC 功能，需要安装 luci-mod-rpc，然后重启 web(nginx/uhttpd) 服务
```shell
opkg install luci-mod-rpc
/etc/init.d/uhttpd restart

# 检查路径 /cgi-bin/luci/rpc
```

PS.

openwrt.ai 构建所需

```
-luci-app-wizard -luci-app-fan luci-app-zerotier luci-app-mwan3 luci-app-watchcat netbird luci-mod-rpc
```
