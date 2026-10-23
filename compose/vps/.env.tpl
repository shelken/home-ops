# ==================== 通用配置 ====================
TZ=Asia/Shanghai
MAIN_DOMAIN=bws://compose-vps/MAIN_DOMAIN

# 部署内部网的host
DEPLOY_HOST=bws://compose-vps/DEPLOY_HOST

DOCKER_PROXY_HOST=bws://compose-vps/DOCKER_PROXY_HOST

# base_dir
DATA_BASE_DIR=bws://compose-vps/DATA_BASE_DIR

# ==================== Caddy ====================
CADDY_CLOUDFLARE_API_TOKEN=bws://compose-vps/CLOUDFLARE_API_TOKEN
ENVOY_EXTERNAL_IP=bws://compose-vps/ENVOY_EXTERNAL_IP

# ==================== CrowdSec ====================
CROWDSEC_LOCAL_API_URL=bws://compose-vps/CROWDSEC_LOCAL_API_URL
CROWDSEC_AGENT_PASSWORD=bws://compose-vps/CROWDSEC_AGENT_PASSWORD
CROWDSEC_FIREWALL_BOUNCER_API_KEY=bws://compose-vps/CROWDSEC_FIREWALL_BOUNCER_API_KEY
CROWDSEC_CADDY_BOUNCER_API_KEY=bws://compose-vps/CROWDSEC_CADDY_BOUNCER_API_KEY

# ==================== MosDNS ====================
REMOTE_DNS_SERVER_1=bws://compose-vps/REMOTE_DNS_SERVER_1
REMOTE_DNS_SERVER_2=bws://compose-vps/REMOTE_DNS_SERVER_2

# ==================== Victoria-Logs ====================
VICTORIA_LOGS_HOST=bws://compose-vps/VICTORIA_LOGS_HOST
VICTORIA_LOGS_PORT=9428

# ==================== Kopia ====================
KOPIA_REPO_PASSWORD=bws://compose-vps/KOPIA_REPO_PASSWORD
KOPIA_WEBHOOK_URL=bws://compose-vps/KOPIA_WEBHOOK_URL

# ==================== OpenList ====================
OPENLIST_ADMIN_USERNAME=bws://compose-vps/OPENLIST_ADMIN_USERNAME
OPENLIST_ADMIN_PASSWORD=bws://compose-vps/OPENLIST_ADMIN_PASSWORD
OPENLIST_S3_ACCESS_KEY_ID=bws://compose-vps/OPENLIST_S3_ACCESS_KEY_ID
OPENLIST_S3_SECRET_ACCESS_KEY=bws://compose-vps/OPENLIST_S3_SECRET_ACCESS_KEY

# ==================== sb-sync ====================
SB_SYNC_SERVER_PRIVATE_KEY=bws://compose-vps/SB_SYNC_SERVER_PRIVATE_KEY
