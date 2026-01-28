#!/usr/bin/env bash
set -euo pipefail
PORT=${PORT:-8000}
ROOT_DIR="/home/kdbbbu/WebDev/Apple Watch profit or loss notifier"

echo "Serving '${ROOT_DIR}' on http://localhost:${PORT}/"
python3 -m http.server "${PORT}" --directory "${ROOT_DIR}"