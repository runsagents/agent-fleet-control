#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$PROJECT_ROOT/bin/agent-fleet"
FIXTURE="$PROJECT_ROOT/fixtures/setup-synthetic-repo.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-fleet-writer.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

REPO="$TMP_ROOT/synthetic-payments"
"$FIXTURE" "$REPO" >/dev/null
cd "$REPO"

printf '1..9\n'

output=$("$CLI" new api-agent "Harden synthetic payment API" \
  --path services/payments/api \
  --acceptance "API module tests pass" \
  --verify "./test.sh")
[[ "$output" == *"Created writer api-agent"* ]] || fail "new did not report writer creation"
printf 'ok 1 - creates a writing-agent worktree\n'

API_WORKTREE="$REPO/.agent-fleet/worktrees/api-agent"
[[ -d "$API_WORKTREE" ]] || fail "API worktree was not created"
[[ "$(git -C "$API_WORKTREE" branch --show-current)" == "fleet/api-agent" ]] || fail "wrong API branch"
assert_file "$REPO/.agent-fleet/contracts/api-agent/contract.md"
assert_file "$REPO/.agent-fleet/contracts/api-agent/contract.json"
assert_contains "$REPO/.agent-fleet/contracts/api-agent/contract.json" '"services/payments/api"'
assert_contains "$REPO/.agent-fleet/contracts/api-agent/contract.md" 'API module tests pass'
node -e 'const c=JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); if (c.agent !== "api-agent" || c.allowed_paths[0] !== "services/payments/api") process.exit(1)' \
  "$REPO/.agent-fleet/contracts/api-agent/contract.json" || fail "contract JSON did not parse to the required values"
printf 'ok 2 - records branch, worktree, territory, and contract\n'

"$CLI" new ledger-agent "Reconcile synthetic ledger" \
  --path services/payments/ledger \
  --acceptance "Ledger checks pass" \
  --verify "./test.sh" >/dev/null
LEDGER_WORKTREE="$REPO/.agent-fleet/worktrees/ledger-agent"
[[ -d "$LEDGER_WORKTREE" ]] || fail "ledger worktree was not created"
[[ "$API_WORKTREE" != "$LEDGER_WORKTREE" ]] || fail "writers share a worktree"
printf 'ok 3 - isolates a second writer in a separate worktree\n'

if "$CLI" new payments-agent "Touch the whole synthetic service" \
  --path services/payments \
  --acceptance "Service checks pass" \
  --verify "./test.sh" >"$TMP_ROOT/collision.out" 2>&1; then
  fail "overlapping parent territory was accepted"
fi
grep -Fq 'territory collision' "$TMP_ROOT/collision.out" || fail "collision error is not actionable"
[[ ! -e "$REPO/.agent-fleet/worktrees/payments-agent" ]] || fail "refused writer left a worktree"
printf 'ok 4 - refuses ancestor/descendant territory overlap\n'

if "$CLI" new duplicate-agent "Duplicate exact scope" \
  --path services/payments/api \
  --acceptance "Duplicate" \
  --verify "./test.sh" >/dev/null 2>&1; then
  fail "exact overlap was accepted"
fi
printf 'ok 5 - refuses exact territory overlap\n'

"$CLI" new payments-agent "Approved synthetic integration work" \
  --path services/payments \
  --acceptance "Integration checks pass" \
  --verify "./test.sh" \
  --override >"$TMP_ROOT/override.out"
grep -Fq 'OVERRIDE RECORDED' "$TMP_ROOT/override.out" || fail "override was not visible"
assert_contains "$REPO/.agent-fleet/contracts/payments-agent/contract.json" '"collision_override": true'
printf 'ok 6 - permits and records an explicit override\n'

if "$CLI" new ../escape "Unsafe agent" \
  --path services/payments/webhooks \
  --acceptance "Unsafe" \
  --verify "./test.sh" >/dev/null 2>&1; then
  fail "unsafe agent identifier was accepted"
fi
printf 'ok 7 - rejects unsafe agent identifiers\n'

if "$CLI" new malformed-agent "Unsafe territory" \
  --path services//payments \
  --acceptance "Unsafe" \
  --verify "./test.sh" >/dev/null 2>&1; then
  fail "malformed territory was accepted"
fi
printf 'ok 8 - rejects malformed repository paths\n'

HOOK="$REPO/.git/hooks/post-checkout"
printf '%s\n' '#!/usr/bin/env bash' 'exit 9' >"$HOOK"
chmod +x "$HOOK"
if "$CLI" new rollback-agent "Exercise transactional rollback" \
  --path docs \
  --acceptance "Failed creation leaves no state" \
  --verify "./test.sh" >/dev/null 2>&1; then
  fail "worktree creation unexpectedly survived failing hook"
fi
[[ ! -e "$REPO/.agent-fleet/contracts/rollback-agent" ]] || fail "failed creation left a contract"
[[ ! -e "$REPO/.agent-fleet/worktrees/rollback-agent" ]] || fail "failed creation left a worktree"
if git show-ref --verify --quiet refs/heads/fleet/rollback-agent; then
  fail "failed creation left a branch"
fi
if git worktree list --porcelain | grep -Fq '.agent-fleet/worktrees/rollback-agent'; then
  fail "failed creation left a worktree registration"
fi
printf 'ok 9 - rolls back branch, worktree registration, and contract on partial Git failure\n'

printf 'PASS writer-isolation: 9 assertions\n'
