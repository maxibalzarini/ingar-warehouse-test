#!/usr/bin/env bash
set -euo pipefail

PAYLOAD="${1:-INGAR_Warehouse_Server_1.0.51_SERVER_READY_R2_PAYLOAD.zip}"
TARGET="$HOME/ingar-warehouse-server"

if [[ ! -f "$PAYLOAD" ]]; then
  echo "ERROR: no encuentro $PAYLOAD en $(pwd)" >&2
  exit 1
fi

if [[ -s /usr/local/share/nvm/nvm.sh ]]; then
  source /usr/local/share/nvm/nvm.sh
  nvm install 22 >/dev/null
  nvm use 22 >/dev/null
fi

if [[ "$(node -p 'process.versions.node.split(".")[0]')" != "22" ]]; then
  echo "ERROR: se requiere Node.js 22. Actual: $(node -v)" >&2
  exit 2
fi

# Limpia cualquier self-test anterior que haya quedado escuchando en puerto aleatorio.
pkill -f "$HOME/ingar-warehouse-server/scripts/server-self-test.js" 2>/dev/null || true

if [[ -x "$TARGET/STOP_INGAR.sh" ]]; then
  "$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true
fi

rm -rf "$TARGET.new"
mkdir -p "$TARGET.new"
unzip -q -o "$PAYLOAD" -d "$TARGET.new"

SRC="$TARGET.new/ingar-warehouse-server"
if [[ ! -f "$SRC/INSTALL_SERVER.sh" ]]; then
  echo "ERROR: payload inválido; falta INSTALL_SERVER.sh" >&2
  exit 3
fi

rm -rf "$TARGET.previous"
if [[ -d "$TARGET" ]]; then
  mv "$TARGET" "$TARGET.previous"
fi

mv "$SRC" "$TARGET"
rm -rf "$TARGET.new"

cd "$TARGET"

# ZIP/GitHub no preserva de forma confiable el bit ejecutable del payload.
chmod +x ./INSTALL_SERVER.sh ./START_INGAR.sh ./STOP_INGAR.sh ./STATUS_INGAR.sh ./scripts/install-linux-native.sh

./INSTALL_SERVER.sh
./START_INGAR.sh
./STATUS_INGAR.sh

echo
echo "SERVER READY R2"
echo "Abrí la pestaña PORTS y usá el puerto 4317."
echo "Mantenelo Private hasta crear el primer Administrador General."
