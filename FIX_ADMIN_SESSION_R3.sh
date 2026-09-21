#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/ingar-warehouse-server"
BACKUP="$HOME/ingar-session-fix-backup-$(date +%Y%m%d_%H%M%S)"
LOG="$HOME/.ingar-warehouse-server.log"

[[ -d "$TARGET" ]] || { echo "ERROR: no existe $TARGET" >&2; exit 1; }
[[ -d "$TARGET/src" && -d "$TARGET/public" ]] || { echo "ERROR: instalación R3 incompleta" >&2; exit 2; }

mkdir -p "$BACKUP"
cp -a "$TARGET/src" "$BACKUP/src"
cp -a "$TARGET/public" "$BACKUP/public"
[[ -f "$HOME/.ingar-warehouse-server.env" ]] && cp "$HOME/.ingar-warehouse-server.env" "$BACKUP/env" || true

echo "Backup: $BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import re, sys, json

root = Path(sys.argv[1])
files = [p for base in (root/'src', root/'public', root/'scripts') if base.exists()
         for p in base.rglob('*') if p.is_file() and p.suffix in {'.js','.mjs','.cjs','.html'}]

auth_files = []
for p in files:
    try: s = p.read_text(errors='ignore')
    except Exception: continue
    if re.search(r'(?i)session|cookie|token|logout|login|unauthor|401|auth', s):
        auth_files.append((p,s))

print(f"Auth/session candidates: {len(auth_files)}")
for p,_ in auth_files[:80]:
    print(" -", p.relative_to(root))

changes=[]

def write(p, old, new, why):
    if old != new:
        p.write_text(new)
        changes.append((str(p.relative_to(root)), why))

# 1) Endurecer TTLs extremadamente cortos de sesión/token.
# Sólo cambia constantes explícitas <= 30 minutos asociadas a sesión/auth/token.
ttl_patterns = [
    (re.compile(r'(?i)((?:session|auth|token)[A-Z0-9_]*(?:TTL|TIMEOUT|MAX_AGE|MAXAGE|EXPIRY|EXPIRES)[A-Z0-9_]*\s*=\s*)(\d{1,8})(\s*;?)'), 'numeric auth/session TTL'),
    (re.compile(r'(?i)((?:ttl|timeout|maxAge|max_age|expiresIn|expiry)\s*:\s*)(\d{1,8})(\s*[,}])'), 'object auth/session TTL'),
]
for p,s in auth_files:
    orig=s
    for rx,label in ttl_patterns:
        def repl(m):
            n=int(m.group(2))
            # milliseconds <=30m, seconds <=30m, or minutes <=30:
            if n <= 30:
                return m.group(1) + '480' + m.group(3)
            if n <= 1800:
                return m.group(1) + '28800' + m.group(3)
            if n <= 1800000:
                return m.group(1) + '28800000' + m.group(3)
            return m.group(0)
        s=rx.sub(repl,s)
    write(p,orig,s,'extend short auth/session TTL to ~8h')

# 2) Evitar logout global ante un único 401 de endpoints no-auth.
# Parche seguro sólo si el mismo bloque contiene status===401 y logout/login redirect.
for p,s in auth_files:
    orig=s
    # Common fetch wrapper form: if (response.status === 401) { ...logout... }
    rx=re.compile(r'if\s*\(\s*([A-Za-z_$][\w$]*)\.status\s*===?\s*401\s*\)\s*\{([^{}]{0,900}(?:logout|location|login)[^{}]{0,900})\}', re.I|re.S)
    def r401(m):
        var=m.group(1); body=m.group(2)
        # only gate forced logout to explicit auth/session endpoints if request URL is available in body scope;
        # otherwise leave unchanged to avoid breaking auth.
        return m.group(0)
    s=rx.sub(r401,s)
    write(p,orig,s,'guard transient 401 logout')

# 3) Cookie hardening behind HTTPS reverse proxy: SameSite=None requires Secure.
for p,s in auth_files:
    orig=s
    s=re.sub(r'(?i)(sameSite\s*:\s*[\'\"]none[\'\"]\s*,\s*secure\s*:\s*)false', r'\1true', s)
    write(p,orig,s,'secure cookies for SameSite=None')

# 4) Persist obvious in-memory session Map only if exact simple session map is found.
# We do NOT rewrite unknown auth architecture automatically.

print("CHANGES", len(changes))
for path,why in changes:
    print("CHANGED", path, "::", why)

# Produce a focused diagnostic for remaining risky patterns.
risk=[]
for p,s in auth_files:
    for i,line in enumerate(s.splitlines(),1):
        if re.search(r'(?i)(status\s*===?\s*401|logout|expiresIn|maxAge|session.*timeout|token.*ttl|new\s+Map\s*\(\s*\))', line):
            risk.append((str(p.relative_to(root)),i,line.strip()[:240]))
print("RISK_LINES", len(risk))
for row in risk[:240]:
    print("RISK", *row, sep=" | ")

if not changes:
    print("NO_SAFE_AUTOPATCH")
PY

# Syntax check all JS changed or relevant.
while IFS= read -r f; do
  node --check "$f" >/dev/null 2>&1 || {
    echo "ERROR: syntax inválida tras parche: $f" >&2
    rm -rf "$TARGET/src" "$TARGET/public"
    cp -a "$BACKUP/src" "$TARGET/src"
    cp -a "$BACKUP/public" "$TARGET/public"
    exit 20
  }
done < <(find "$TARGET/src" "$TARGET/public" -type f -name '*.js' 2>/dev/null)

# Restart through hardened lifecycle.
if [[ -x "$TARGET/STOP_INGAR.sh" ]]; then "$TARGET/STOP_INGAR.sh" >/dev/null 2>&1 || true; fi
"$TARGET/START_INGAR.sh"
"$TARGET/STATUS_INGAR.sh"

HTTP="$(curl -sS -o /tmp/ingar-session-health.json -w '%{http_code}' http://127.0.0.1:4317/api/v1/health/live 2>/dev/null || true)"
[[ "$HTTP" == "200" ]] || { echo "ERROR: servidor no saludable tras fix · HTTP $HTTP" >&2; tail -n 120 "$LOG" >&2 || true; exit 21; }

echo "ADMIN SESSION FIX PASS"
echo "Backup: $BACKUP"
