#!/usr/bin/env bash
set -euo pipefail
PAYLOAD="${1:-INGAR_Warehouse_Server_1.0.51_SERVER_READY_PAYLOAD.zip}"
TARGET="$HOME/ingar-warehouse-server"

if [[ ! -f "$PAYLOAD" ]]; then
  echo "ERROR: no encuentro $PAYLOAD en $(pwd)" >&2
  exit 1
fi

# Codespaces trae nvm en la imagen estándar. Si está disponible, fijamos Node 22.
if [[ -s /usr/local/share/nvm/nvm.sh ]]; then
  # shellcheck disable=SC1091
  source /usr/local/share/nvm/nvm.sh
  nvm install 22 >/dev/null
  nvm use 22 >/dev/null
fi

if [[ "$(node -p 'process.versions.node.split(".")[0]')" != "22" ]]; then
  echo "ERROR: se requiere Node.js 22. Actual: $(node -v)" >&2
  exit 2
fi

rm -rf "$TARGET.new"
mkdir -p "$TARGET.new"
unzip -q -o "$PAYLOAD" -d "$TARGET.new"
SRC="$TARGET.new/ingar-warehouse-server"
if [[ ! -f "$SRC/INSTALL_SERVER.sh" ]]; then
  echo "ERROR: payload inválido; falta INSTALL_SERVER.sh" >&2
  exit 3
fi

# Preserva datos y secreto fuera del código. Sólo se reemplaza la aplicación.
rm -rf "$TARGET.previous"
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$TARGET.previous"; fi
mv "$SRC" "$TARGET"
rm -rf "$TARGET.new"

cd "$TARGET"
./INSTALL_SERVER.sh
./START_INGAR.sh
./STATUS_INGAR.sh

echo
echo "SERVER READY"
echo "Abrí la pestaña PORTS de Codespaces y usá el puerto 4317."
echo "IMPORTANTE: mantenelo Private hasta crear el primer Administrador General."
