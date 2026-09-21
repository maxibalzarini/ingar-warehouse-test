#!/usr/bin/env bash
set -u

TARGET="$HOME/ingar-warehouse-server"
ROUTER="$TARGET/src/http/api-router.js"
ENV_FILE="$HOME/.ingar-warehouse-server.env"
PID_FILE="$HOME/.ingar-warehouse-server.pid"
LOG_FILE="$HOME/.ingar-warehouse-server.log"

echo "[1/6] Verificando archivos..."
for f in "$ROUTER" "$ENV_FILE" "$TARGET/scripts/start-server.js"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: falta $f"
    exit 1
  fi
done

echo "[2/6] Asegurando router limpio..."
python3 - "$ROUTER" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
start = s.find("  // HOTFIX R2.2:")
if start != -1:
    end_marker = "  for (const routeModule of routeModules) {"
    end = s.find(end_marker, start)
    if end == -1:
        raise SystemExit("ERROR: no pude localizar el final del bloque HOTFIX R2.2")
    s = s[:start] + s[end:]
    p.write_text(s)
print("router limpio")
PY
node --check "$ROUTER" || exit 2

echo "[3/6] Deteniendo procesos anteriores..."
if [[ -f "$PID_FILE" ]]; then
  OLD="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD" ]] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PID_FILE"
fi
pkill -f "$TARGET/scripts/start-server.js" 2>/dev/null || true

echo "[4/6] Arrancando Node directamente..."
set -a
source "$ENV_FILE"
set +a
: > "$LOG_FILE"
nohup node "$TARGET/scripts/start-server.js" >>"$LOG_FILE" 2>&1 &
NEWPID=$!
echo "$NEWPID" > "$PID_FILE"
echo "PID $NEWPID"

echo "[5/6] Esperando healthcheck 4317..."
for i in $(seq 1 20); do
  if ! kill -0 "$NEWPID" 2>/dev/null; then
    echo "ERROR: el proceso Node terminó antes del healthcheck."
    echo "---- LOG ----"
    cat "$LOG_FILE" || true
    exit 3
  fi
  CODE="$(curl -sS -o /tmp/ingar-health-visible.json -w '%{http_code}' http://127.0.0.1:${IWC_PORT:-4317}/api/v1/health/live 2>/dev/null || true)"
  echo "intento $i/20 · HTTP ${CODE:-000}"
  if [[ "$CODE" == "200" ]]; then
    echo "[6/6] RECOVERY PASS · PID $NEWPID · puerto ${IWC_PORT:-4317}"
    cat /tmp/ingar-health-visible.json 2>/dev/null || true
    echo
    exit 0
  fi
  sleep 1
done

echo "ERROR: healthcheck no llegó a 200."
echo "---- LOG ----"
cat "$LOG_FILE" || true
exit 4
