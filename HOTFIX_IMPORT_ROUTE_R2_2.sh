#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/ingar-warehouse-server"
ROUTER="$TARGET/src/http/api-router.js"
ASSETS="$TARGET/src/http/routes/assets.js"
IMPORT_UI="$TARGET/public/js/app/13-imports.js"

for f in "$ROUTER" "$ASSETS" "$IMPORT_UI"; do
  [[ -f "$f" ]] || { echo "ERROR: falta $f" >&2; exit 1; }
done

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TARGET/.hotfix-backup-import-route-$STAMP"
mkdir -p "$BACKUP"
cp "$ROUTER" "$BACKUP/api-router.js"
cp "$ASSETS" "$BACKUP/assets.js"
cp "$IMPORT_UI" "$BACKUP/13-imports.js"

python3 - "$ROUTER" "$ASSETS" <<'PY'
from pathlib import Path
import sys

router = Path(sys.argv[1])
assets = Path(sys.argv[2])

a = assets.read_text()
required = [
    "pathname === '/api/v1/imports/assets/template'",
    "pathname === '/api/v1/imports/assets/validate'",
    "pathname === '/api/v1/imports'",
    "'/api/v1/imports/:id/apply'",
]
missing = [x for x in required if x not in a]
if missing:
    raise SystemExit("ERROR: assets.js no contiene las rutas de importación esperadas: " + ", ".join(missing))

s = router.read_text()

old = """async function routeApi(req, res, url, baseContext) {
  const { pathname } = url;
  if (!pathname.startsWith('/api/v1/')) return false;

  for (const routeModule of routeModules) {
"""
new = """async function routeApi(req, res, url, baseContext) {
  const { pathname } = url;
  if (!pathname.startsWith('/api/v1/')) return false;

  // HOTFIX R2.2: las rutas de importación se despachan de forma explícita al
  // módulo assets antes del resto del router. Evita que cualquier handler
  // genérico anterior pueda consumir /api/v1/imports/* y garantiza el mismo
  // contrato en Electron y Server Edition.
  if (pathname === '/api/v1/imports' || pathname.startsWith('/api/v1/imports/')) {
    if (await assets.handle(req, res, url, baseContext)) return true;
  }

  for (const routeModule of routeModules) {
"""

if "HOTFIX R2.2" not in s:
    if old not in s:
        raise SystemExit("ERROR: no encontré el bloque routeApi esperado; no se modifica nada.")
    s = s.replace(old, new, 1)
    router.write_text(s)
PY

node --check "$ROUTER"
node --check "$ASSETS"
node --check "$IMPORT_UI"

cd "$TARGET"

./STOP_INGAR.sh >/dev/null 2>&1 || true
./START_INGAR.sh
./STATUS_INGAR.sh

sleep 1

# Una petición POST sin sesión debe llegar a la ruta y devolver 401.
# 404 significa que el runtime sigue sin exponer el endpoint.
HTTP_CODE="$(curl -sS -o /tmp/ingar-import-route-check.json -w '%{http_code}'   -X POST   -H 'Content-Type: application/json'   --data '{}'   http://127.0.0.1:4317/api/v1/imports/assets/validate || true)"

echo "LOCAL IMPORT ROUTE HTTP $HTTP_CODE"
cat /tmp/ingar-import-route-check.json 2>/dev/null || true
echo

if [[ "$HTTP_CODE" == "404" || "$HTTP_CODE" == "000" ]]; then
  echo "ERROR: /api/v1/imports/assets/validate sigue sin estar expuesto localmente." >&2
  exit 4
fi

if [[ "$HTTP_CODE" != "401" && "$HTTP_CODE" != "403" && "$HTTP_CODE" != "400" && "$HTTP_CODE" != "422" ]]; then
  echo "ERROR: respuesta inesperada al validar la ruta: HTTP $HTTP_CODE" >&2
  exit 5
fi

if [[ -n "${CODESPACE_NAME:-}" ]]; then
  PUBLIC_URL="https://${CODESPACE_NAME}-4317.app.github.dev/api/v1/imports/assets/validate"
  PUBLIC_CODE="$(curl -sS -o /tmp/ingar-import-route-public-check.txt -w '%{http_code}'     -X POST     -H 'Content-Type: application/json'     --data '{}'     "$PUBLIC_URL" || true)"
  echo "CODESPACES IMPORT ROUTE HTTP $PUBLIC_CODE"
  if [[ "$PUBLIC_CODE" == "404" ]]; then
    echo "ERROR: Codespaces devuelve 404 aunque el backend local responde. Revisar forwarding/publicación del puerto 4317." >&2
    exit 6
  fi
fi

echo
echo "HOTFIX IMPORT ROUTE PASS"
echo "Ruta activa: POST /api/v1/imports/assets/validate"
echo "Backup: $BACKUP"
