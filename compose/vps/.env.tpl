# ==================== 通用配置 ====================
TZ=Asia/Shanghai
MAIN_DOMAIN=azure://shelken-homelab/compose-vps/MAIN_DOMAIN

# 部署内部网的host
DEPLOY_HOST=azure://shelken-homelab/compose-vps/DEPLOY_HOST

DOCKER_PROXY_HOST=azure://shelken-homelab/compose-vps/DOCKER_PROXY_HOST

# base_dir
DATA_BASE_DIR=azure://shelken-homelab/compose-vps/DATA_BASE_DIR

# ==================== Caddy ====================
CADDY_CLOUDFLARE_API_TOKEN=azure://shelken-homelab/compose-vps/CLOUDFLARE_API_TOKEN

# ==================== CrowdSec ====================
CROWDSEC_LOCAL_API_URL=azure://shelken-homelab/compose-vps/CROWDSEC_LOCAL_API_URL
CROWDSEC_AGENT_PASSWORD=azure://shelken-homelab/compose-vps/CROWDSEC_AGENT_PASSWORD

# ==================== MosDNS ====================
REMOTE_DNS_SERVER_1=azure://shelken-homelab/compose-vps/REMOTE_DNS_SERVER_1
REMOTE_DNS_SERVER_2=azure://shelken-homelab/compose-vps/REMOTE_DNS_SERVER_2

# ==================== Victoria-Logs ====================
VICTORIA_LOGS_HOST=azure://shelken-homelab/compose-vps/VICTORIA_LOGS_HOST
VICTORIA_LOGS_PORT=9428

# ==================== Kopia ====================
KOPIA_REPO_PASSWORD=azure://shelken-homelab/compose-vps/KOPIA_REPO_PASSWORD
KOPIA_SERVER_USERNAME=azure://shelken-homelab/compose-vps/KOPIA_SERVER_USERNAME
KOPIA_SERVER_PASSWORD=azure://shelken-homelab/compose-vps/KOPIA_SERVER_PASSWORD
