#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$PROJECT_ROOT/bin/agent-fleet"
FIXTURE="$PROJECT_ROOT/fixtures/setup-synthetic-repo.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-fleet-gates.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

REPO="$TMP_ROOT/synthetic-payments"
"$FIXTURE" "$REPO" >/dev/null
cd "$REPO"

printf '1..11\n'

"$CLI" new webhook-agent "Validate synthetic webhook signatures" \
  --path services/payments/webhooks \
  --acceptance "Webhook checks pass" \
  --verify "./test.sh" >/dev/null
printf 'ok 1 - creates a contract with a verification gate\n'

if "$CLI" receipt webhook-agent --reviewer "R. Reviewer" --risk "None reported" >"$TMP_ROOT/preverify.out" 2>&1; then
  fail "receipt was created without verification"
fi
grep -Fq 'successful verification' "$TMP_ROOT/preverify.out" || fail "pre-verification error is unclear"
printf 'ok 2 - blocks a receipt before verification\n'

"$CLI" verify webhook-agent >"$TMP_ROOT/verify.out"
grep -Fq 'Verification passed' "$TMP_ROOT/verify.out" || fail "passing verification not reported"
EVIDENCE="$REPO/.agent-fleet/contracts/webhook-agent/verification.log"
assert_contains "$EVIDENCE" 'synthetic payments checks passed'
[[ "$(<"$REPO/.agent-fleet/contracts/webhook-agent/verification.exit")" == "0" ]] || fail "exit code not captured"
FIRST_EVIDENCE=$(<"$REPO/.agent-fleet/contracts/webhook-agent/verification.evidence")
[[ -f "$FIRST_EVIDENCE/verification.log" ]] || fail "attempt-specific evidence missing"
FIRST_DIGEST=$(<"$FIRST_EVIDENCE/verification.digest")
[[ "$(git hash-object "$FIRST_EVIDENCE/verification.log")" == "$FIRST_DIGEST" ]] || fail "evidence digest mismatch"
printf 'ok 3 - runs and captures immutable attempt-specific verification evidence\n'

MAIN_BEFORE=$(git rev-parse HEAD)
"$CLI" receipt webhook-agent \
  --reviewer "R. Reviewer" \
  --risk "Synthetic fixture only; production integration untested" >"$TMP_ROOT/receipt.out"
RECEIPT_MD=$(sed -n 's/^Receipt: //p' "$TMP_ROOT/receipt.out")
[[ -f "$RECEIPT_MD" ]] || fail "Markdown receipt missing"
RECEIPT_JSON=${RECEIPT_MD%.md}.json
[[ -f "$RECEIPT_JSON" ]] || fail "JSON receipt missing"
assert_contains "$RECEIPT_JSON" '"reviewer_identity": "R. Reviewer"'
assert_contains "$RECEIPT_JSON" '"verification_exit_code": 0'
assert_contains "$RECEIPT_MD" 'Synthetic fixture only; production integration untested'
node -e '
  const r=JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (r.reviewer_identity !== "R. Reviewer" || r.verification_exit_code !== 0 || r.verification_evidence !== process.argv[2]) process.exit(1);
' "$RECEIPT_JSON" "$FIRST_EVIDENCE/verification.log" || fail "receipt JSON did not parse to the required values"
printf 'ok 4 - emits machine-readable and human-readable receipts\n'

[[ "$(git rev-parse HEAD)" == "$MAIN_BEFORE" ]] || fail "main checkout moved"
[[ -z "$(git remote)" ]] || fail "synthetic fixture unexpectedly has a remote"
grep -Fq 'No merge or push was performed.' "$TMP_ROOT/receipt.out" || fail "non-merging guarantee not reported"
printf 'ok 5 - never merges or pushes\n'

WORKTREE="$REPO/.agent-fleet/worktrees/webhook-agent"
printf '\nverified=true\n' >>"$WORKTREE/services/payments/webhooks/module.conf"
git -C "$WORKTREE" add services/payments/webhooks/module.conf
git -C "$WORKTREE" -c user.name='Synthetic Agent' -c user.email='agent@example.invalid' commit -m 'synthetic webhook change' >/dev/null
if "$CLI" receipt webhook-agent --reviewer "R. Reviewer" --risk "None" >"$TMP_ROOT/stale.out" 2>&1; then
  fail "receipt accepted stale evidence"
fi
grep -Fq 'current commit' "$TMP_ROOT/stale.out" || fail "stale-evidence error is unclear"
printf 'ok 6 - rejects evidence from an earlier commit\n'

"$CLI" verify webhook-agent >/dev/null
"$CLI" receipt webhook-agent --reviewer "R. Reviewer" --risk "None reported" >/dev/null
SECOND_EVIDENCE=$(<"$REPO/.agent-fleet/contracts/webhook-agent/verification.evidence")
[[ "$SECOND_EVIDENCE" != "$FIRST_EVIDENCE" ]] || fail "new verification reused old evidence directory"
[[ -f "$FIRST_EVIDENCE/verification.log" ]] || fail "new verification removed old evidence"
[[ "$(git hash-object "$FIRST_EVIDENCE/verification.log")" == "$FIRST_DIGEST" ]] || fail "new verification changed old evidence"
printf 'ok 7 - allows a fresh receipt without mutating earlier evidence\n'

printf '\ndirty=true\n' >>"$WORKTREE/services/payments/webhooks/module.conf"
if "$CLI" verify webhook-agent >"$TMP_ROOT/dirty.out" 2>&1; then
  fail "verification accepted a dirty worktree"
fi
if "$CLI" receipt webhook-agent --reviewer "R. Reviewer" --risk "None" >>"$TMP_ROOT/dirty.out" 2>&1; then
  fail "receipt accepted a dirty worktree"
fi
grep -Fq 'uncommitted or untracked changes' "$TMP_ROOT/dirty.out" || fail "dirty-tree error is unclear"
git -C "$WORKTREE" restore services/payments/webhooks/module.conf
printf 'ok 8 - refuses verification and receipts for uncommitted content\n'

git -C "$WORKTREE" switch -q -c rogue
if "$CLI" verify webhook-agent >"$TMP_ROOT/branch.out" 2>&1; then
  fail "verification accepted the wrong branch"
fi
if "$CLI" receipt webhook-agent --reviewer "R. Reviewer" --risk "None" >>"$TMP_ROOT/branch.out" 2>&1; then
  fail "receipt accepted the wrong branch"
fi
grep -Fq "expected 'fleet/webhook-agent'" "$TMP_ROOT/branch.out" || fail "branch error is unclear"
git -C "$WORKTREE" switch -q fleet/webhook-agent
printf 'ok 9 - binds verification and receipts to the contracted branch\n'

"$CLI" new dirty-agent "Exercise a verification side effect" \
  --path services/payments/api \
  --acceptance "Dirty verification is rejected" \
  --verify "printf 'changed=true\\n' >> services/payments/api/module.conf; exit 23" >/dev/null
set +e
"$CLI" verify dirty-agent >"$TMP_ROOT/dirty-command.out" 2>&1
dirty_status=$?
set -e
[[ "$dirty_status" -eq 125 ]] || fail "dirty verification returned $dirty_status instead of 125"
assert_contains "$TMP_ROOT/dirty-command.out" 'verification left uncommitted or untracked changes'
if "$CLI" receipt dirty-agent --reviewer "R. Reviewer" --risk "Known side effect" >/dev/null 2>&1; then
  fail "receipt accepted a verification integrity failure"
fi
printf 'ok 10 - fails a command that changes the verified worktree\n'

"$CLI" new ledger-agent "Exercise a failing gate" \
  --path services/payments/ledger \
  --acceptance "Failure is captured" \
  --verify "printf 'intentional synthetic failure\\n'; exit 23" >/dev/null
if "$CLI" verify ledger-agent >"$TMP_ROOT/failverify.out" 2>&1; then
  fail "failing verification returned success"
fi
[[ "$(<"$REPO/.agent-fleet/contracts/ledger-agent/verification.exit")" == "23" ]] || fail "failing exit code not captured"
assert_contains "$REPO/.agent-fleet/contracts/ledger-agent/verification.log" 'intentional synthetic failure'
if "$CLI" receipt ledger-agent --reviewer "R. Reviewer" --risk "Known failure" >/dev/null 2>&1; then
  fail "receipt accepted failing verification"
fi
printf 'ok 11 - preserves failure evidence and blocks its receipt\n'

printf 'PASS merge-gates: 11 assertions\n'
