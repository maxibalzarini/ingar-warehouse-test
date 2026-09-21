#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/ingar-warehouse-server"
ROUTER="$TARGET/src/http/api-router.js"
LOG="$HOME/.ingar-warehouse-server.log"
PID="$HOME/.ingar-warehouse-server.pid"

[[ -f "$ROUTER" ]] || { echo "ERROR: no existe $ROUTER" >&2; exit 1; }

python3 - "$ROUTER" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
block = """  // HOTFIX R2.2: las rutas de importación se despachan de forma explícita al
  // módulo assets antes del resto del router. Evita que cualquier handler
  // genérico anterior pueda consumir /api/v1/imports/* y garantiza el mismo
  // contrato en Electron y Server Edition.
  if (pathname === '/api/v1/imports' || pathname.startsWith('/api/v1/imports/')) {
    if (await assets.handle(req, res, url, baseContext)) return true;
  }

"""
if block in s:
    s = s.replace(block, "", 1)
    p.write_text(s)
print("ROUTER RESTAURADO")
PY

node --check "$ROUTER"

if [[ -f "$PID" ]]; then
  OLD="$(cat "$PID" 2>/dev/null || true)"
  if [[ -n "$OLD" ]] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PID"
fi

pkill -f "$TARGET/scripts/start-server.js" 2>/dev/null || true

cd "$TARGET"
./START_INGAR.sh
./STATUS_INGAR.sh

HTTP="$(curl -sS -o /tmp/ingar-health.json -w '%{http_code}' http://127.0.0.1:4317/api/v1/health/live || true)"
echo "HEALTH HTTP $HTTP"
cat /tmp/ingar-health.json 2>/dev/null || true
echo

if [[ "$HTTP" != "200" ]]; then
  echo "ERROR: servidor no recuperado. Último log:" >&2
  tail -n 120 "$LOG" >&2 || true
  exit 2
fi

echo "RECOVERY PASS · puerto 4317 activo"
