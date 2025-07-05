#!/usr/bin/env bash
# /srv/tests/test_nginx_hardening.sh
# Basic unit test for hardened NGINX provisioning

set -euo pipefail

NGINX_SITE_CONF="/etc/nginx/sites-available/woodpecker.conf"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/woodpecker.conf"

echo "[Test] Checking if NGINX is installed..."
if ! command -v nginx >/dev/null 2>&1; then
  echo "[FAIL] NGINX is not installed"
  exit 1
fi
echo "[PASS] NGINX is installed."

echo "[Test] Checking if site config exists..."
if [ ! -f "$NGINX_SITE_CONF" ]; then
  echo "[FAIL] Site config $NGINX_SITE_CONF missing"
  exit 1
fi
echo "[PASS] Site config exists."

echo "[Test] Checking if site is enabled..."
if [ ! -L "$NGINX_SITE_LINK" ]; then
  echo "[FAIL] Site symlink $NGINX_SITE_LINK missing"
  exit 1
fi
echo "[PASS] Site symlink exists."

echo "[Test] Testing NGINX configuration..."
if ! nginx -t; then
  echo "[FAIL] NGINX config test failed"
  exit 1
fi
echo "[PASS] NGINX config test passed."

echo "[Test] Reloading NGINX to confirm no errors..."
if ! systemctl reload nginx; then
  echo "[FAIL] NGINX reload failed"
  exit 1
fi
echo "[PASS] NGINX reload succeeded."

echo "[Test] All tests passed."
exit 0
