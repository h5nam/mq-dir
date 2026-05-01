#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PORT="${PORT:-8765}"
echo "mq-dir prototype → http://localhost:${PORT}/mq-dir.html"
exec python3 -m http.server "${PORT}"
