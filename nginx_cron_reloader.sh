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

NGINX_TEST_OUTPUT=$(docker exec "$NGINX_CONTAINER_NAME" nginx -t 2>&1)

if echo "$NGINX_TEST_OUTPUT" | grep -q 'test is successful'; then
    docker exec "$NGINX_CONTAINER_NAME" nginx -s reload > /dev/null 2>&1
    sudo rm "$NGINX_RELOAD_TRIGGER_FILE"
    echo "$(date): ✅ Nginx reloaded."
else
    echo "$(date): ❌ Nginx reload aborted. Error in configuration:"
    echo "$NGINX_TEST_OUTPUT"
    exit 1
fi
