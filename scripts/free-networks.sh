#!/usr/bin/env bash

# docs: https://docs.k3s.io/zh/advanced#%E9%85%8D%E7%BD%AE-http-%E4%BB%A3%E7%90%86

# 初始化变量
DELETE_MODE=false

# 解析命令行参数
while getopts "d" opt; do
  case $opt in
    d)
      DELETE_MODE=true
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# 移动参数位置，使 $1 指向第一个非选项参数
shift $((OPTIND-1))

# 用法说明
if [ $# -lt 2 ]; then
  echo "用法: $0 [-d] <ssh目标主机> <代理IP> [代理端口，默认7890]"
  echo "选项:"
  echo "  -d    删除代理配置"
  echo "示例:"
  echo "  $0 root@192.168.1.10 10.0.0.2 7890      # 设置代理"
  echo "  $0 -d root@192.168.1.10 10.0.0.2        # 删除代理"
  exit 1
fi

REMOTE="$1"
PROXY_IP="$2"
PORT="${3:-7890}"

# 构建远程命令
CMD="set -e

for FILE in /etc/systemd/system/k3s-agent.service.env /etc/systemd/system/k3s.service.env; do
  if [ -f \"\$FILE\" ]; then
    echo \"[\$FILE] 存在，正在处理配置...\"
    
    # 删除现有的代理配置（使用单行sed命令）
    sudo sed -i -e '/^CONTAINERD_HTTP_PROXY=/d' -e '/^CONTAINERD_HTTPS_PROXY=/d' -e '/^CONTAINERD_NO_PROXY=/d' -e '/^HTTP_PROXY=/d' -e '/^HTTPS_PROXY=/d' -e '/^NO_PROXY=/d' \"\$FILE\""

if [ "$DELETE_MODE" = false ]; then
  CMD="$CMD
    # 添加新的代理配置
    sudo tee -a \"\$FILE\" << EOF
HTTP_PROXY=http://$PROXY_IP:$PORT
HTTPS_PROXY=http://$PROXY_IP:$PORT
NO_PROXY=localhost,::1,$PROXY_IP,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.cluster.local.,.cluster.local,.svc
EOF"
fi

CMD="$CMD
  else
    echo \"[\$FILE] 不存在，跳过\"
  fi
done

sudo systemctl daemon-reexec
sudo systemctl restart k3s-agent || true
sudo systemctl restart k3s || true"

# 添加完成消息
if [ "$DELETE_MODE" = true ]; then
  CMD="$CMD"$'\necho "[完成] 已删除代理配置并尝试重启 k3s/k3s-agent 服务。"'
else
  CMD="$CMD"$'\necho "[完成] 已更新代理配置并尝试重启 k3s/k3s-agent 服务。"'
fi

# 执行远程命令
ssh "$REMOTE" "$CMD"