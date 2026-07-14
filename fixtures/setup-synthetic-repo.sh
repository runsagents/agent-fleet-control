#!/usr/bin/env bash
set -euo pipefail

destination=${1:-}
if [[ -z "$destination" ]]; then
  destination=$(mktemp -d "${TMPDIR:-/tmp}/synthetic-payments.XXXXXX")
fi

if [[ -e "$destination" && -n "$(ls -A "$destination" 2>/dev/null)" ]]; then
  printf 'error: destination is not empty: %s\n' "$destination" >&2
  exit 1
fi

mkdir -p \
  "$destination/services/payments/api" \
  "$destination/services/payments/ledger" \
  "$destination/services/payments/webhooks"

printf '%s\n' \
  '# Synthetic payments fixture' \
  '' \
  'This repository is generated test data. It is not a production service and contains no real credentials, customers, or payment logic.' \
  >"$destination/README.md"

printf '%s\n' 'module=api' 'mode=synthetic' >"$destination/services/payments/api/module.conf"
printf '%s\n' 'module=ledger' 'mode=synthetic' >"$destination/services/payments/ledger/module.conf"
printf '%s\n' 'module=webhooks' 'mode=synthetic' >"$destination/services/payments/webhooks/module.conf"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'for module in api ledger webhooks; do' \
  '  grep -Fq "module=$module" "services/payments/$module/module.conf"' \
  '  grep -Fq "mode=synthetic" "services/payments/$module/module.conf"' \
  'done' \
  "printf 'synthetic payments checks passed\\n'" \
  >"$destination/test.sh"
chmod +x "$destination/test.sh"

git -C "$destination" init -q
git -C "$destination" config user.name "Synthetic Fixture"
git -C "$destination" config user.email "fixture@example.invalid"
git -C "$destination" add README.md services test.sh
git -C "$destination" commit -q -m "Initialize synthetic payments fixture"

printf '%s\n' "$destination"
