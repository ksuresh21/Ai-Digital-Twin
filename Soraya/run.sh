#!/usr/bin/env bash
# Starts Soraya's local server and opens the interface.
#
#   ./run.sh                 # whatever settings.json says
#   ./run.sh --offline       # no model, no key, no network
#   ./run.sh --port 9000
set -euo pipefail
cd "$(dirname "$0")"

PORT=8765
for arg in "$@"; do
  case "$arg" in
    --offline) export SORAYA_BRAIN=echo ;;
    --port=*)  PORT="${arg#*=}" ;;
  esac
done
# Support `--port 9000` as well as `--port=9000`.
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--port" && -n "${2:-}" ]] && PORT="$2"
  shift
done

if [[ ! -d assets/characters/Soraya/Idle ]]; then
  echo "==> No character frames yet — drawing placeholders"
  python3 scripts/make_placeholders.py
fi

# Open the browser once the port is actually accepting connections, rather
# than after a fixed sleep that is either too short or wastes your time.
(
  for _ in $(seq 1 40); do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
      open "http://127.0.0.1:$PORT"
      exit 0
    fi
    sleep 0.25
  done
) &

exec python3 -m soraya.server --port "$PORT"
