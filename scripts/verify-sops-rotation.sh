#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-sops-rotation.sh
# 遵循 principle-prove-it-works 准则的确定性验证脚本
# 严查真实产物（AKV、Git 仓库明文、信封接收者、双钥解密自检），杜绝自欺欺人
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

pass_count=0
fail_count=0

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo -e "  [${GREEN}PASS${NC}] $desc"
    echo -e "         预期: $expected"
    echo -e "         实际: $actual"
    pass_count=$((pass_count + 1))
  else
    echo -e "  [${RED}FAIL${NC}] $desc"
    echo -e "         预期: $expected"
    echo -e "         实际: $actual"
    fail_count=$((fail_count + 1))
  fi
}

assert_cmd() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo -e "  [${GREEN}PASS${NC}] $desc"
    pass_count=$((pass_count + 1))
  else
    echo -e "  [${RED}FAIL${NC}] $desc"
    echo -e "         执行失败: $*"
    fail_count=$((fail_count + 1))
  fi
}

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}      SOPS In-Cluster 密钥轮换全链路确定性证明测试          ${NC}"
echo -e "${BLUE}============================================================${NC}"

# 1. 提取 .sops.yaml 中的当前公钥定义
echo -e "\n${BLUE}--> 1. 提取声明层公钥定义 (.sops.yaml)${NC}"
pub_home_ops=$(awk '/&home-ops/{print $NF}' "$ROOT_DIR/.sops.yaml")
pub_admin_mio=$(awk '/&admin_mio/{print $NF}' "$ROOT_DIR/.sops.yaml")
echo "  .sops.yaml &home-ops : $pub_home_ops"
echo "  .sops.yaml &admin_mio: $pub_admin_mio"

# 2. 检查本地 home-ops.txt 是否与声明一致
echo -e "\n${BLUE}--> 2. 验证本地密钥文件 (~/.config/sops/age/home-ops.txt)${NC}"
if [ -f "$HOME/.config/sops/age/home-ops.txt" ]; then
  local_home_ops_pub=$(age-keygen -y "$HOME/.config/sops/age/home-ops.txt")
  assert_eq "本地 home-ops.txt 对应公钥 == .sops.yaml 定义" "$pub_home_ops" "$local_home_ops_pub"
else
  echo -e "  [${RED}FAIL${NC}] 未找到 $HOME/.config/sops/age/home-ops.txt"
  fail_count=$((fail_count + 1))
fi

# 3. 检查 Azure Key Vault 里的私钥公钥是否与声明一致
echo -e "\n${BLUE}--> 3. 验证 Azure Key Vault (shelken-homelab/sops/SOPS_PRIVATE_KEY)${NC}"
akv_priv=$(az keyvault secret show --vault-name shelken-homelab --name sops --query value -o tsv | jq -r .SOPS_PRIVATE_KEY 2>/dev/null || true)
if [ -n "$akv_priv" ]; then
  akv_pub=$(echo "$akv_priv" | age-keygen -y 2>/dev/null)
  assert_eq "Azure Key Vault 私钥对应公钥 == .sops.yaml 定义" "$pub_home_ops" "$akv_pub"
else
  echo -e "  [${RED}FAIL${NC}] 无法从 Azure Key Vault 获取 SOPS_PRIVATE_KEY"
  fail_count=$((fail_count + 1))
fi

# 4. 关键验证：检查 secret.sops.yaml 内部明文私钥是否与声明一致
echo -e "\n${BLUE}--> 4. 验证 secret.sops.yaml 内部载荷 (防止私钥回滚)${NC}"
secret_file="$ROOT_DIR/k8s/components/common/sops/secret.sops.yaml"
if [ -f "$secret_file" ]; then
  decrypted_priv=$(SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/home-ops.txt" sops -d "$secret_file" 2>/dev/null | awk '/age.agekey:/{print $NF}' || true)
  if [ -n "$decrypted_priv" ]; then
    decrypted_pub=$(echo "$decrypted_priv" | age-keygen -y 2>/dev/null)
    assert_eq "secret.sops.yaml 内部明文对应公钥 == .sops.yaml 定义" "$pub_home_ops" "$decrypted_pub"
  else
    echo -e "  [${RED}FAIL${NC}] 无法解密 secret.sops.yaml 提取 age.agekey"
    fail_count=$((fail_count + 1))
  fi
else
  echo -e "  [${RED}FAIL${NC}] 文件不存在: $secret_file"
  fail_count=$((fail_count + 1))
fi

# 5. 验证两个文件的 SOPS 接收者信封是否包含新钥匙
echo -e "\n${BLUE}--> 5. 验证 SOPS 接收者信封是否对齐${NC}"
assert_cmd "secret.sops.yaml 包含 &home-ops 接收者" grep -q "$pub_home_ops" "$secret_file"
assert_cmd "secret.sops.yaml 包含 &admin_mio 接收者" grep -q "$pub_admin_mio" "$secret_file"

cluster_secret_file="$ROOT_DIR/k8s/components/common/sops/cluster-secret.sops.yaml"
assert_cmd "cluster-secret.sops.yaml 包含 &home-ops 接收者" grep -q "$pub_home_ops" "$cluster_secret_file"
assert_cmd "cluster-secret.sops.yaml 包含 &admin_mio 接收者" grep -q "$pub_admin_mio" "$cluster_secret_file"

# 6. 验证双钥匙独立解密业务密文能力
echo -e "\n${BLUE}--> 6. 验证双钥匙独立解密业务密文能力${NC}"
assert_cmd "使用 home-ops.txt 独立解密 cluster-secret.sops.yaml" env SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/home-ops.txt" sops -d "$cluster_secret_file"
if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
  assert_cmd "使用 keys.txt (admin_mio) 独立解密 cluster-secret.sops.yaml" env SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" sops -d "$cluster_secret_file"
fi

# 7. 验证 Kustomize 构建能力
echo -e "\n${BLUE}--> 7. 验证 Kustomize 架构完整性${NC}"
assert_cmd "kustomize build k8s/infra/staging 编译成功" mise exec -- kustomize build k8s/infra/staging

echo -e "\n${BLUE}============================================================${NC}"
echo -e "证明测试结果: 通过 [${GREEN}$pass_count${NC}] | 失败 [${RED}$fail_count${NC}]"
echo -e "${BLUE}============================================================${NC}"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
