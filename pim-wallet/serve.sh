#!/usr/bin/env bash
set -euo pipefail
PORT=${PORT:-8000}
export PORT

echo "Serving with GitLab OAuth proxy on http://localhost:${PORT}/"
python3 "$(dirname "$0")/dev_server.py"