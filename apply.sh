#!/bin/bash
set -e

if [ -f "./.env" ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✅ Environment variables loaded."
else
  echo "❌ Error: .env not found."
  exit 1
fi

echo "🔍 Installing dependencies..."
BINARY_DEPS=("fail2ban-client" "nft" "envsubst")
MISSING_PKGS=()

if ! command -v fail2ban-client &> /dev/null; then MISSING_PKGS+=("fail2ban"); fi
if ! command -v nft &> /dev/null; then MISSING_PKGS+=("nftables"); fi
if ! command -v envsubst &> /dev/null; then MISSING_PKGS+=("gettext-base"); fi

if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
    echo "📥 Installing missing packages: ${MISSING_PKGS[*]}..."
    sudo apt update
    sudo apt install -y --no-install-recommends "${MISSING_PKGS[@]}"
else
    echo "✅ All dependencies are present."
fi

echo "⚙️  Configuring Nftables structure..."

if systemctl is-active --quiet fail2ban; then
    echo "🚦 Stopping Fail2ban temporarily to apply network changes..."
    sudo systemctl stop fail2ban
fi

NFT_DEST="/etc/nftables.d/f2b-table.conf"
sudo mkdir -p /etc/nftables.d

if [ -f "nftables/f2b-structure.nft" ]; then
    sudo cp "nftables/f2b-structure.nft" "$NFT_DEST"
else
    echo "❌ Error: nftables/f2b-structure.nft not found."
    exit 1
fi

sudo nft delete table inet f2b-table 2>/dev/null || true

if ! sudo nft -f "$NFT_DEST"; then
    echo "❌ Error: Failed to apply nftables structure."
    exit 1
fi
echo "✅ Nftables structure applied successfully."

NFT_INCLUDE_LINE='include "/etc/nftables.d/*.conf"'
if ! sudo grep -Fxq "$NFT_INCLUDE_LINE" /etc/nftables.conf; then
    echo "➕ Adding include line to /etc/nftables.conf..."
    echo "$NFT_INCLUDE_LINE" | sudo tee -a /etc/nftables.conf > /dev/null
else
    echo "✅ Include line already exists in /etc/nftables.conf"
fi

sudo systemctl enable nftables > /dev/null 2>&1

FAIL2BAN_DIR="/etc/fail2ban"
LOCAL_IPS=$(hostname -I)
INFRA_NETS="127.0.0.1/8 ::1 172.16.0.0/12 192.168.0.0/16"

echo "⚙️  Applying global configuration..."
echo "[DEFAULT]
backend = auto
ignoreip = $INFRA_NETS $LOCAL_IPS
enabled = false
" | sudo tee "$FAIL2BAN_DIR/jail.d/00-global-overrides.local" > /dev/null

echo "☁️  Downloading Cloudflare ranges..."
mkdir -p "$(dirname "$NGINX_CLOUDFLARE_FILE")"
CLOUDFLARE_V4=$(curl -s https://www.cloudflare.com/ips-v4)
CLOUDFLARE_V6=$(curl -s https://www.cloudflare.com/ips-v6)

{
  echo "# Generated: $(date)"
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
  echo "set_real_ip_from 172.16.0.0/12;"
  echo "set_real_ip_from 192.168.0.0/16;"
  echo "set_real_ip_from 10.0.0.0/8;"
  for ip in $CLOUDFLARE_V4 $CLOUDFLARE_V6; do echo "set_real_ip_from $ip;"; done
} | sudo tee "$NGINX_CLOUDFLARE_FILE" > /dev/null

if [ ! -f "$NGINX_BLACKLIST_FILE" ]; then
    echo "# Nginx Blacklist" | sudo tee "$NGINX_BLACKLIST_FILE" > /dev/null
fi
sudo chmod 664 "$NGINX_BLACKLIST_FILE"
echo "⚙️  Configuring Fail2ban..."

envsubst < ./actions/nginx-docker-block.tpl | sudo tee "$FAIL2BAN_DIR/action.d/nginx-docker-block.conf" > /dev/null

sudo cp ./filters/*.conf "$FAIL2BAN_DIR/filter.d/"
for tpl in ./jails/*.tpl; do
  jail_name=$(basename "$tpl" .tpl).local
  echo "⛓️  Processing jail: $jail_name"
  envsubst < "$tpl" | sudo tee "$FAIL2BAN_DIR/jail.d/$jail_name" > /dev/null
done

echo "🔄 Restarting Fail2ban..."
sudo systemctl restart fail2ban

echo "🛡️  Verifying Nginx configuration..."
NGINX_TEST_OUTPUT=$(docker exec "$NGINX_CONTAINER_NAME" nginx -t 2>&1)

if echo "$NGINX_TEST_OUTPUT" | grep -q 'test is successful'; then
    docker exec "$NGINX_CONTAINER_NAME" nginx -s reload > /dev/null 2>&1
    echo "✅ Nginx reloaded."
else
    echo "❌ Nginx reload aborted. Error in configuration:"
    echo "$NGINX_TEST_OUTPUT"
    exit 1
fi

echo "📅 Configuring scheduled task (Cron) for the Reload Manager..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELOAD_MANAGER_PATH="$SCRIPT_DIR/nginx_cron_reloader.sh"
chmod +x "$RELOAD_MANAGER_PATH"

CRON_LINE="* * * * * $RELOAD_MANAGER_PATH >> $SCRIPT_DIR/logs/nginx_cron_reloader.log 2>&1"
if sudo crontab -l 2>/dev/null | grep -Fq "$RELOAD_MANAGER_PATH"; then
    echo "✅ Reload Manager is already configured in the cron."
else
    (sudo crontab -l 2>/dev/null; echo "$CRON_LINE") | sudo crontab -
    echo "🕐 Reload Manager added to cron: executing every minute."
fi

echo "🚀 Fail2ban Filters deployed and protected."
