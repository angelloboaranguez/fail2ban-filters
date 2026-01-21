#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/.env" ]; then
  export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
  echo "❌ Error: .env not found."
  exit 1
fi

if [ ! -f "$NGINX_RELOAD_TRIGGER_FILE" ]; then
    exit 0
fi

echo "$(date): 🔄 Changes detected. Validating Nginx..."

if docker exec "$NGINX_CONTAINER_NAME" nginx -t > /dev/null 2>&1; then
    docker exec "$NGINX_CONTAINER_NAME" nginx -s reload
    sudo rm "$NGINX_RELOAD_TRIGGER_FILE"
    echo "$(date): ✅ Nginx reloaded."
else
    echo "$(date): ❌ Error in configuration. Reload aborted."
fi
