#!/usr/bin/env bash
set -euo pipefail
TARGET="$HOME/ingar-warehouse-server"
BACKUP="$HOME/ingar-admin-session-stable-$(date +%Y%m%d_%H%M%S)"
[[ -d "$TARGET/public" && -d "$TARGET/src" ]] || { echo "ERROR: instalación INGAR no encontrada" >&2; exit 1; }
mkdir -p "$BACKUP"
cp -a "$TARGET/public" "$BACKUP/public"
cp -a "$TARGET/src" "$BACKUP/src"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
public=root/'public'
js=[p for p in public.rglob('*.js') if p.is_file()]
changed=[]

for p in js:
    s=p.read_text(errors='ignore')
    if not re.search(r'(?i)auth|token|login|session', s):
        continue
    old=s
    s=re.sub(r'\bsessionStorage\b', 'localStorage', s)
    if s!=old:
        p.write_text(s)
        changed.append((p,'auth storage -> localStorage'))

allfiles=[p for base in (root/'src',root/'public') for p in base.rglob('*.js') if p.is_file()]
for p in allfiles:
    s=p.read_text(errors='ignore'); old=s
    if not re.search(r'(?i)auth|session|token|cookie|login', s):
        continue
    s=re.sub(r"(?i)(expiresIn\s*[:=]\s*['\"])(?:[1-9]|[12][0-9]|30)m(['\"])", r"\g<1>8h\2", s)
    s=re.sub(r"(?i)(expiresIn\s*[:=]\s*['\"])(?:1)h(['\"])", r"\g<1>8h\2", s)
    def nfix(m):
        n=int(m.group(2))
        if n <= 1800000: return m.group(1)+'28800000'+m.group(3)
        return m.group(0)
    s=re.sub(r'(?i)((?:maxAge|sessionTTL|sessionTimeout|tokenTTL|authTTL)\s*[:=]\s*)(\d+)(\s*[,;}])', nfix, s)
    s=re.sub(r'(?<!\d)(?:15|20|30|60)\s*\*\s*60\s*\*\s*1000(?!\d)', '8 * 60 * 60 * 1000', s)
    if s!=old:
        p.write_text(s); changed.append((p,'auth/session TTL -> 8h'))

shim = r'''
;(() => {
  if (window.__INGAR_FETCH_STABLE__) return;
  window.__INGAR_FETCH_STABLE__ = true;
  const nativeFetch = window.fetch.bind(window);
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  window.fetch = async function(input, init) {
    let response;
    try { response = await nativeFetch(input, init); } catch (e) {
      await sleep(350);
      return nativeFetch(input, init);
    }
    if ([401,408,429,502,503,504].includes(response.status)) {
      await sleep(response.status === 401 ? 250 : 450);
      try {
        const retry = await nativeFetch(input, init);
        return retry;
      } catch (_) {
        return response;
      }
    }
    return response;
  };
})();
'''
candidates=[]
for p in js:
    s=p.read_text(errors='ignore')
    score=(5 if re.search(r'(?i)login|logout|auth',s) else 0)+(3 if 'fetch(' in s else 0)+(2 if p.name in {'app.js','main.js','index.js'} else 0)
    if score: candidates.append((score,p,s))
if candidates:
    _,p,s=max(candidates,key=lambda x:x[0])
    if '__INGAR_FETCH_STABLE__' not in s:
        p.write_text(shim+s)
        changed.append((p,'transient fetch retry guard'))

print('CHANGED',len(changed))
for p,why in changed:
    print(' -',p.relative_to(root),'::',why)
if not changed:
    raise SystemExit('ERROR: no se encontró una superficie de sesión/auth segura para corregir')
PY

while IFS= read -r f; do node --check "$f" >/dev/null || { echo "ERROR JS: $f" >&2; rm -rf "$TARGET/public" "$TARGET/src"; cp -a "$BACKUP/public" "$TARGET/public"; cp -a "$BACKUP/src" "$TARGET/src"; exit 20; }; done < <(find "$TARGET/public" "$TARGET/src" -type f -name '*.js')

"$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true
"$TARGET/START_INGAR.sh"
"$TARGET/STATUS_INGAR.sh"

echo "ADMIN SESSION STABILITY FIX PASS"
echo "BACKUP=$BACKUP"
