# ==================== 通用配置 ====================
TZ=Asia/Shanghai
MAIN_DOMAIN=bws://compose-sakamoto/MAIN_DOMAIN
DOCKER_DATA_DIR=bws://compose-sakamoto/DOCKER_DATA_DIR

# ==================== 用户配置 ====================
UID=501
GID=20

# ==================== Caddy ====================
CADDY_CLOUDFLARE_API_TOKEN=bws://compose-sakamoto/CLOUDFLARE_API_TOKEN

# ==================== MinIO ====================
MINIO_DATA_DIR=bws://compose-sakamoto/MINIO_DATA_DIR
MINIO_ROOT_USER=bws://compose-sakamoto/MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=bws://compose-sakamoto/MINIO_ROOT_PASSWORD

# ==================== Mirror ====================
MIRROR_DATA_DIR=bws://compose-sakamoto/MIRROR_DATA_DIR

# ==================== Kopia (Cloud) ====================
KOPIA_MAIN_PASSWORD=bws://compose-sakamoto/KOPIA_MAIN_PASSWORD
KOPIA_WEBHOOK_URL=bws://compose-sakamoto/KOPIA_WEBHOOK_URL

# ==================== Kopia Local ====================
KOPIA_LOCAL_REPO_PASSWORD=bws://compose-sakamoto/KOPIA_LOCAL_REPO_PASSWORD
