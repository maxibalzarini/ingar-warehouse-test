#!/usr/bin/env bash
set -euo pipefail
TARGET="$HOME/ingar-warehouse-server"
[[ -d "$TARGET" ]] || { echo "ERROR: no existe $TARGET. Ejecutá primero SETUP_INGAR_SERVER_R3.sh" >&2; exit 1; }
[[ -f "$TARGET/scripts/start-server.js" ]] || { echo "ERROR: instalación incompleta; falta scripts/start-server.js" >&2; exit 2; }

cat > "$TARGET/START_INGAR.sh" <<'START_EOF'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$HOME/ingar-warehouse-server"
PID_FILE="$HOME/.ingar-warehouse-server.pid"
LOG_FILE="$HOME/.ingar-warehouse-server.log"
ENV_FILE="$HOME/.ingar-warehouse-server.env"
PORT="4317"
[[ -f "$TARGET/scripts/start-server.js" ]] || { echo "ERROR: falta $TARGET/scripts/start-server.js" >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "ERROR: falta $ENV_FILE" >&2; exit 1; }
if [[ -s /usr/local/share/nvm/nvm.sh ]]; then source /usr/local/share/nvm/nvm.sh; fi
if command -v nvm >/dev/null 2>&1; then nvm use 22 >/dev/null 2>&1 || nvm install 22 >/dev/null; nvm use 22 >/dev/null 2>&1; fi
NODE_BIN="$(command -v node)"
[[ "$(node -p 'process.versions.node.split(".")[0]')" == "22" ]] || { echo "ERROR: Node 22 requerido" >&2; exit 2; }
if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    CMD="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true)"
    if [[ "$CMD" == *"$TARGET/scripts/start-server.js"* ]]; then
      CODE="$(curl -sS -o /tmp/ingar-live.json -w '%{http_code}' "http://127.0.0.1:$PORT/api/v1/health/live" 2>/dev/null || true)"
      if [[ "$CODE" == "200" ]]; then echo "INGAR ya activo · PID $PID · puerto $PORT"; exit 0; fi
      kill "$PID" 2>/dev/null || true; sleep 1
    fi
  fi
  rm -f "$PID_FILE"
fi
set -a
source "$ENV_FILE"
set +a
: >> "$LOG_FILE"
if command -v setsid >/dev/null 2>&1; then nohup setsid "$NODE_BIN" "$TARGET/scripts/start-server.js" </dev/null >>"$LOG_FILE" 2>&1 & else nohup "$NODE_BIN" "$TARGET/scripts/start-server.js" </dev/null >>"$LOG_FILE" 2>&1 & fi
PID=$!
echo "$PID" > "$PID_FILE"
for i in $(seq 1 30); do
  kill -0 "$PID" 2>/dev/null || { echo "ERROR: Node terminó durante el arranque" >&2; tail -n 100 "$LOG_FILE" >&2 || true; rm -f "$PID_FILE"; exit 3; }
  CODE="$(curl -sS -o /tmp/ingar-live.json -w '%{http_code}' "http://127.0.0.1:${IWC_PORT:-4317}/api/v1/health/live" 2>/dev/null || true)"
  if [[ "$CODE" == "200" ]]; then echo "INGAR ACTIVE · PID $PID · puerto ${IWC_PORT:-4317} · detached"; exit 0; fi
  sleep 1
done
echo "ERROR: healthcheck no llegó a 200" >&2
tail -n 120 "$LOG_FILE" >&2 || true
exit 4
START_EOF

cat > "$TARGET/STOP_INGAR.sh" <<'STOP_EOF'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$HOME/ingar-warehouse-server"
PID_FILE="$HOME/.ingar-warehouse-server.pid"
[[ -f "$PID_FILE" ]] || { echo "INGAR detenido"; exit 0; }
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[[ -n "$PID" ]] || { rm -f "$PID_FILE"; echo "INGAR detenido"; exit 0; }
if kill -0 "$PID" 2>/dev/null; then
  CMD="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true)"
  [[ "$CMD" == *"$TARGET/scripts/start-server.js"* ]] || { echo "PID $PID no pertenece a INGAR; no se mata." >&2; rm -f "$PID_FILE"; exit 2; }
  kill "$PID" 2>/dev/null || true
  for _ in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$PID" 2>/dev/null; then kill -KILL "$PID" 2>/dev/null || true; fi
fi
rm -f "$PID_FILE"
echo "INGAR detenido"
STOP_EOF

cat > "$TARGET/STATUS_INGAR.sh" <<'STATUS_EOF'
#!/usr/bin/env bash
set -euo pipefail
TARGET="$HOME/ingar-warehouse-server"
PID_FILE="$HOME/.ingar-warehouse-server.pid"
LOG_FILE="$HOME/.ingar-warehouse-server.log"
PORT="${IWC_PORT:-4317}"
[[ -f "$PID_FILE" ]] || { echo "DOWN · sin PID"; exit 1; }
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null || { echo "DOWN · PID inválido"; exit 1; }
CMD="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true)"
[[ "$CMD" == *"$TARGET/scripts/start-server.js"* ]] || { echo "DOWN · PID ajeno"; exit 1; }
CODE="$(curl -sS -o /tmp/ingar-status.json -w '%{http_code}' "http://127.0.0.1:$PORT/api/v1/health/live" 2>/dev/null || true)"
[[ "$CODE" == "200" ]] || { echo "DEGRADED · PID $PID vivo · HTTP ${CODE:-000}"; tail -n 80 "$LOG_FILE" 2>/dev/null || true; exit 2; }
echo "UP · PID $PID · HTTP 200 · puerto $PORT · detached"
STATUS_EOF

chmod +x "$TARGET/START_INGAR.sh" "$TARGET/STOP_INGAR.sh" "$TARGET/STATUS_INGAR.sh"
"$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true
"$TARGET/START_INGAR.sh"
"$TARGET/STATUS_INGAR.sh"
CODE="$(curl -sS -o /tmp/ingar-r3-import-route.json -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data '{}' http://127.0.0.1:4317/api/v1/imports/assets/validate || true)"
[[ "$CODE" == "401" ]] || { echo "ERROR: import validate respondió HTTP $CODE" >&2; exit 5; }
if [[ -n "${CODESPACE_NAME:-}" ]] && command -v gh >/dev/null 2>&1; then
  gh codespace ports visibility 4317:public -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
  echo "PUBLIC URL: https://${CODESPACE_NAME}-4317.app.github.dev/control"
fi
echo "RECOVERY R3 PERSISTENT PASS"
