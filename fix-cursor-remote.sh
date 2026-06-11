#!/bin/bash
# Linux 服务器：修复 Cursor Remote hooks / 僵死进程
set -euo pipefail
echo ""
echo "========== Cursor remote fix =========="
BACKUP_DIR="/root/cursor-fix-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_if_exists() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "$BACKUP_DIR/" 2>/dev/null || true
  fi
}

echo "[1] hooks.json"
for HOOKS in /root/.cursor/hooks.json; do
  if [ -f "$HOOKS" ]; then
    if ! python3 -c "import json; json.load(open('$HOOKS'))" 2>/dev/null; then
      backup_if_exists "$HOOKS"
      mkdir -p "$(dirname "$HOOKS")"
    fi
  fi
done
mkdir -p /root/.cursor
cat > /root/.cursor/hooks.json <<'EOF'
{"version":1,"hooks":{}}
EOF
echo "  OK /root/.cursor/hooks.json"

echo "[2] stale cursor-server"
pkill -f 'cursor-server' 2>/dev/null || true
pkill -f 'multiplex-server' 2>/dev/null || true
rm -f /run/user/0/cursor-remote-*.token.* 2>/dev/null || true
rm -f /run/user/0/cursor-remote-lock.* 2>/dev/null || true
echo "  done"

echo "[3] disk"
df -h / | tail -1
echo "========== remote fix done =========="
