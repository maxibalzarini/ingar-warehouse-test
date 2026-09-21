#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/ingar-warehouse-server"
if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: no existe $TARGET" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TARGET/.hotfix-backup-optional-document-$STAMP"
mkdir -p "$BACKUP"

cp "$TARGET/src/services/user-service.js" "$BACKUP/user-service.js"
cp "$TARGET/src/services/bootstrap-access-service.js" "$BACKUP/bootstrap-access-service.js"
cp "$TARGET/public/index.html" "$BACKUP/index.html"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])

# 1) Usuarios: documento real opcional, con identidad técnica interna AUTO-* si se omite.
p = root / 'src/services/user-service.js'
s = p.read_text()
old = """function validateUserInput(input, creating = true) {
  const person = input.person || {};
  const result = {
    username: normalizeUsername(input.username),
    fullName: requiredString(person.fullName, 'person.fullName', { min: 3, max: 160 }),
    documentType: requiredString(person.documentType, 'person.documentType', { min: 1, max: 30 }),
    documentNumber: requiredString(person.documentNumber, 'person.documentNumber', { min: 1, max: 60 }),
"""
new = """function normalizeOptionalDocument(person = {}, currentPerson = null) {
  const suppliedType = String(person.documentType || '').trim();
  const suppliedNumber = String(person.documentNumber || '').trim();
  if (!suppliedType && !suppliedNumber) {
    if (currentPerson && String(currentPerson.documentType || '').toUpperCase() === 'INTERNO'
      && String(currentPerson.documentNumber || '').toUpperCase().startsWith('AUTO-')) {
      return { documentType: currentPerson.documentType, documentNumber: currentPerson.documentNumber };
    }
    return { documentType: 'INTERNO', documentNumber: `AUTO-${randomUUID()}` };
  }
  if (!suppliedType || !suppliedNumber) {
    throw Object.assign(new Error('Si informás documento, completá tipo y número. Ambos campos son opcionales.'), { status: 422, code: 'DOCUMENT_PAIR_INCOMPLETE' });
  }
  return {
    documentType: requiredString(suppliedType, 'person.documentType', { min: 1, max: 30 }),
    documentNumber: requiredString(suppliedNumber, 'person.documentNumber', { min: 1, max: 60 })
  };
}

function validateUserInput(input, creating = true, currentPerson = null) {
  const person = input.person || {};
  const document = normalizeOptionalDocument(person, currentPerson);
  const result = {
    username: normalizeUsername(input.username),
    fullName: requiredString(person.fullName, 'person.fullName', { min: 3, max: 160 }),
    documentType: document.documentType,
    documentNumber: document.documentNumber,
"""
if old not in s:
    raise SystemExit('ERROR: patrón user-service validateUserInput no encontrado')
s = s.replace(old, new, 1)

old2 = """  const normalized = validateUserInput({
    username: input.username ?? current.username,
    person: { ...current.person, ...(input.person || {}) },
    roleIds: input.roleIds ?? current.roles.map((role) => role.id),
    siteId: input.siteId,
    locationId: input.locationId
  }, false);
"""
new2 = """  const mergedPerson = { ...current.person, ...(input.person || {}) };
  if (String(current.person.documentType || '').toUpperCase() === 'INTERNO'
      && String(current.person.documentNumber || '').toUpperCase().startsWith('AUTO-')
      && !String(input.person?.documentType || '').trim()
      && !String(input.person?.documentNumber || '').trim()) {
    mergedPerson.documentType = current.person.documentType;
    mergedPerson.documentNumber = current.person.documentNumber;
  }
  const normalized = validateUserInput({
    username: input.username ?? current.username,
    person: mergedPerson,
    roleIds: input.roleIds ?? current.roles.map((role) => role.id),
    siteId: input.siteId,
    locationId: input.locationId
  }, false, current.person);
"""
if old2 not in s:
    raise SystemExit('ERROR: patrón user-service updateUser no encontrado')
s = s.replace(old2, new2, 1)
p.write_text(s)

# 2) Primer Administrador: documento real opcional.
p = root / 'src/services/bootstrap-access-service.js'
s = p.read_text()
old = """  const identity = pendingCreation ? {
    username: desiredUsername,
    fullName: requiredString(fullName, 'fullName', { min: 3, max: 160 }),
    documentType: requiredString(documentType, 'documentType', { min: 2, max: 30 }).toUpperCase(),
    documentNumber: requiredString(documentNumber, 'documentNumber', { min: 3, max: 60 })
  } : null;
"""
new = """  const suppliedDocumentType = String(documentType || '').trim();
  const suppliedDocumentNumber = String(documentNumber || '').trim();
  if (pendingCreation && Boolean(suppliedDocumentType) !== Boolean(suppliedDocumentNumber)) {
    throw Object.assign(new Error('Si informás documento, completá tipo y número. Ambos campos son opcionales.'), { status: 422, code: 'INITIAL_SETUP_DOCUMENT_PAIR_INCOMPLETE' });
  }
  const identity = pendingCreation ? {
    username: desiredUsername,
    fullName: requiredString(fullName, 'fullName', { min: 3, max: 160 }),
    documentType: suppliedDocumentType ? requiredString(suppliedDocumentType, 'documentType', { min: 2, max: 30 }).toUpperCase() : 'INTERNO',
    documentNumber: suppliedDocumentNumber ? requiredString(suppliedDocumentNumber, 'documentNumber', { min: 3, max: 60 }) : `AUTO-${randomUUID()}`
  } : null;
"""
if old not in s:
    raise SystemExit('ERROR: patrón bootstrap identity no encontrado')
s = s.replace(old, new, 1)
p.write_text(s)

# 3) UI: sacar required y marcar opcional.
p = root / 'public/index.html'
s = p.read_text()
pairs = [
('<label>Tipo de documento<input id="initial-setup-document-type" name="documentType" minlength="2" maxlength="30" required></label>',
 '<label>Tipo de documento <span class="small">(opcional)</span><input id="initial-setup-document-type" name="documentType" minlength="2" maxlength="30"></label>'),
('<label>Número de documento<input id="initial-setup-document-number" name="documentNumber" minlength="3" maxlength="60" autocomplete="off" required></label>',
 '<label>Número de documento <span class="small">(opcional)</span><input id="initial-setup-document-number" name="documentNumber" minlength="3" maxlength="60" autocomplete="off"></label>'),
('<label>Tipo de documento / identificador<input id="user-document-type" maxlength="30" required></label>',
 '<label>Tipo de documento / identificador <span class="small">(opcional)</span><input id="user-document-type" maxlength="30"></label>'),
('<label>Número de documento / identificador<input id="user-document-number" maxlength="60" required></label>',
 '<label>Número de documento / identificador <span class="small">(opcional)</span><input id="user-document-number" maxlength="60"></label>')
]
for old, new in pairs:
    if old not in s:
        raise SystemExit(f'ERROR: patrón UI no encontrado: {old[:60]}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

node --check "$TARGET/src/services/user-service.js"
node --check "$TARGET/src/services/bootstrap-access-service.js"

cd "$TARGET"
node scripts/server-self-test.js

./STOP_INGAR.sh >/dev/null 2>&1 || true
./START_INGAR.sh
./STATUS_INGAR.sh

echo
echo "HOTFIX OPTIONAL DOCUMENT PASS"
echo "Documento real opcional. Si se omite, Warehouse usa INTERNO/AUTO-* sólo como identidad técnica interna."
echo "Backup: $BACKUP"
