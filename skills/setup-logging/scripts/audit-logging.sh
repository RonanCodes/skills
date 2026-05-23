#!/usr/bin/env bash
# audit-logging.sh <repo-path> — heuristic check that an app is "diagnosable":
# structured logging that EMITS, request context with trace_id, trace_id FE→BE,
# Cloudflare observability on, Sentry + PostHog wired, and the two silent-failure
# gotchas (DO configureLogger, configure() guard race).
#
# Grep-based heuristic — confirm FAILs by reading the flagged files. Ground truth
# for "logs actually emit" is a `wrangler tail` smoke (this script can't run that).
set -uo pipefail
REPO="${1:?usage: audit-logging.sh <repo-path>}"
[[ -d "$REPO" ]] || { echo "✘ not a dir: $REPO" >&2; exit 2; }
cd "$REPO"
SRC="src"; [[ -d "$SRC" ]] || SRC="."
PKG="package.json"; WR="$(ls wrangler.jsonc wrangler.toml wrangler.json 2>/dev/null | head -1)"
pass=0; warn=0; fail=0
say()  { printf '  %s %s\n' "$1" "$2"; }
ok()   { say "✅" "$1"; pass=$((pass+1)); }
wn()   { say "⚠️ " "$1"; warn=$((warn+1)); }
no()   { say "❌" "$1"; fail=$((fail+1)); }
has()  { grep -rqiE "$1" "$SRC" 2>/dev/null; }

echo "=== logging audit: $REPO ==="

# 1. structured logger present
if [[ -f "$PKG" ]] && grep -qiE '@logtape/logtape|"pino"|"winston"' "$PKG"; then ok "structured logger dependency present"; else no "no structured logger dep (logtape/pino/winston) in package.json"; fi
# 2. console sink (so wrangler tail / Workers Logs see it)
if has 'getConsoleSink|new ConsoleSink|transport.*console'; then ok "console sink configured"; else no "no console sink — logs won't reach wrangler tail / Workers Logs"; fi
# 3. request context carrying ids
if has 'AsyncLocalStorage|withRequestLogContext|requestContext'; then ok "request log context (AsyncLocalStorage) present"; else wn "no request log context — log lines won't carry trace_id/userId/orgId"; fi
# 4. trace_id end-to-end
if has 'trace[_-]?id|x-[a-z]+-trace-id|TRACE_ID_HEADER'; then ok "trace_id present (FE→BE correlation)"; else no "no trace_id — can't correlate FE/BE/Sentry/PostHog"; fi
# 5. Cloudflare observability
# Handles BOTH json/jsonc ("observability": { "enabled": true }) and toml ([observability]\n enabled = true)
if [[ -n "$WR" ]] && grep -qiE 'observability' "$WR" && grep -qiE '"enabled"[^,}]*true|enabled[[:space:]]*=[[:space:]]*true' "$WR"; then ok "Cloudflare observability enabled ($WR)"; else no "observability NOT enabled in ${WR:-<no wrangler config>} — no historical Workers Logs (tail is live-only)"; fi
# 6. Sentry
if has '@sentry|SENTRY_DSN|withSentry'; then ok "Sentry wired"; else wn "Sentry not wired"; fi
# 7. PostHog
if has 'posthog|POSTHOG_'; then ok "PostHog wired"; else wn "PostHog not wired"; fi

# 8. GOTCHA: Durable Objects (and queues/cron) must call configureLogger themselves
DO_FILES=$(grep -rliE 'extends *DurableObject|implements *DurableObject' "$SRC" 2>/dev/null || true)
if [[ -n "$DO_FILES" ]]; then
  bad=""
  while IFS= read -r f; do
    if grep -qiE "log\(" "$f" && ! grep -qiE 'configureLogger' "$f"; then bad="$bad $f"; fi
  done <<< "$DO_FILES"
  if [[ -n "$bad" ]]; then no "DO uses log() but never configureLogger (logs vanish in DO isolate):$bad"; else ok "Durable Objects configure logging"; fi
else
  ok "no Durable Objects (gotcha n/a)"
fi
# 9. GOTCHA: configured-guard set before async configure() resolves
if has 'void configure\(' || grep -rqzoiE 'configured *= *true[^;]*;[^]]*configure\(' "$SRC" 2>/dev/null; then
  wn "possible guard race: 'configured=true' / fire-and-forget 'void configure(...)' — if configure() is slow/throws, logging silently disables. Await it; set guard on success."
else
  ok "no obvious configure() guard race"
fi

echo "---"
verdict="no"; [[ $fail -eq 0 && $warn -le 1 ]] && verdict="yes"; [[ $fail -eq 0 && $warn -gt 1 ]] && verdict="partial"; [[ $fail -gt 0 && $((pass)) -ge 4 ]] && verdict="partial"
echo "  pass=$pass warn=$warn fail=$fail  →  DIAGNOSABLE: $verdict"
echo "  (confirm FAILs by reading the files; verify emission with a 'wrangler tail' smoke.)"
