
要在OpenWrt 的LuCI 中开启RPC 功能，需要安装 luci-mod-rpc，然后重启 web(uhttpd) 服务
```shell
opkg install luci-mod-rpc
/etc/init.d/uhttpd restart

# 检查路径 /cgi-bin/luci/rpc
```

PS.

openwrt.ai 构建所需

```
# 必装
luci-app-zerotier luci-app-watchcat
# 后装（减少固件问题）
# sing-box为自建所需
bird2c luci-mod-rpc luci-app-mwan3 sing-box
```
