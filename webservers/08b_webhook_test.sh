#!/usr/bin/env bash
# /srv/provision/08b_test_github_webhook.sh
# Temporary Flask webhook echo service on /github-webhook/ for GitHub IP testing

set -euo pipefail

log() {
  echo -e "\033[1;35m[Webhook Test]\033[0m $1"
}

fail() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
  exit 1
}

command -v python3 >/dev/null || fail "Python 3 is required"
command -v pip3 >/dev/null || fail "pip3 is required"

log "Installing Flask (temporary)..."
pip3 install --quiet flask

cat <<'EOF' > /tmp/github_webhook_test.py
from flask import Flask, request
app = Flask(__name__)

@app.route('/github-webhook/', methods=['POST'])
def webhook():
    print("Webhook Received:")
    print(request.headers)
    print(request.json)
    return '', 204

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

log "Launching test webhook listener at http://ci.local:8000/github-webhook/"
python3 /tmp/github_webhook_test.py
