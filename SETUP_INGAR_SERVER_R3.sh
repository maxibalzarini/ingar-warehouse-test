#!/usr/bin/env bash
set -euo pipefail

PAYLOAD="${1:-INGAR_Warehouse_Server_1.0.51_SERVER_READY_R3_PAYLOAD.zip}"
TARGET="$HOME/ingar-warehouse-server"
NEW="$HOME/ingar-warehouse-server.new"
PREV="$HOME/ingar-warehouse-server.previous"

fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ -f "$PAYLOAD" ]] || fail "no encuentro $PAYLOAD en $(pwd)"

if [[ -s /usr/local/share/nvm/nvm.sh ]]; then source /usr/local/share/nvm/nvm.sh; fi
if command -v nvm >/dev/null 2>&1; then
  nvm use 22 >/dev/null 2>&1 || { nvm install 22 >/dev/null; nvm use 22 >/dev/null; }
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
ABI="$(node -p 'process.versions.modules')"
[[ "$MAJOR" == "22" && "$ABI" == "127" ]] || fail "se requiere Node 22 / ABI 127; actual $(node -v) / ABI $ABI"
echo "Node $(node -v) · ABI $ABI"

rm -rf "$NEW"
mkdir -p "$NEW"
unzip -q -o "$PAYLOAD" -d "$NEW"
SRC="$NEW/ingar-warehouse-server"
[[ -f "$SRC/INSTALL_SERVER.sh" ]] || fail "payload inválido"
chmod +x "$SRC"/*.sh "$SRC"/scripts/*.sh

BIND_REL="vendor/sqlite-driver/native/linux-x64/node-v127/better_sqlite3.node"
if [[ -f "$TARGET/$BIND_REL" && ! -f "$SRC/$BIND_REL" ]]; then
  mkdir -p "$(dirname "$SRC/$BIND_REL")"
  cp "$TARGET/$BIND_REL" "$SRC/$BIND_REL"
  chmod 755 "$SRC/$BIND_REL"
  echo "SQLite native ABI 127 reutilizado desde instalación existente."
fi

echo "Validando candidato R3..."
(
  cd "$SRC"
  ./INSTALL_SERVER.sh
)
echo "CANDIDATO R3 VALIDADO"

if [[ -x "$TARGET/STOP_INGAR.sh" ]]; then "$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true; fi
rm -rf "$PREV"
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$PREV"; fi
mv "$SRC" "$TARGET"
rm -rf "$NEW"

rollback(){
  echo "ARRANQUE R3 FALLÓ · restaurando versión anterior..." >&2
  if [[ -x "$TARGET/STOP_INGAR.sh" ]]; then "$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true; fi
  rm -rf "$TARGET.failed"
  mv "$TARGET" "$TARGET.failed" 2>/dev/null || true
  if [[ -d "$PREV" ]]; then
    mv "$PREV" "$TARGET"
    chmod +x "$TARGET"/*.sh "$TARGET"/scripts/*.sh 2>/dev/null || true
    "$TARGET/START_INGAR.sh" || true
  fi
  exit 9
}

cd "$TARGET"
./START_INGAR.sh || rollback
./STATUS_INGAR.sh || rollback

CODE="$(curl -sS -o /tmp/ingar-r3-import-route.json -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data '{}' http://127.0.0.1:4317/api/v1/imports/assets/validate || true)"
echo "IMPORT VALIDATE ROUTE · HTTP $CODE"
if [[ "$CODE" != "401" ]]; then
  echo "Respuesta:"; cat /tmp/ingar-r3-import-route.json 2>/dev/null || true; echo
  rollback
fi

echo
echo "SERVER READY R3"
echo "Puerto 4317 activo · schema 053 · importación expuesta · DB preservada."


# R3 persistence hardening: detach Node from terminal and publish Codespaces port for client demo.
RECOVERY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/RECOVER_R3_PERSISTENT.sh"
if [[ -f "$RECOVERY_SCRIPT" ]]; then
  bash "$RECOVERY_SCRIPT"
else
  echo "ERROR: falta $RECOVERY_SCRIPT" >&2
  exit 10
fi
