#!/usr/bin/env bash
# Type-checks every edge function, the way each one is actually built.
#
# `supabase functions deploy` bundles rather than type-checks, so nothing on the deploy path
# catches a type error — two of these had been failing for a while with nothing to notice it.
#
# A function with its own deno.json needs it passed as the config, or its imports don't resolve and
# every one of them "fails" for a reason that has nothing to do with its code. Note the `--config=`
# form: written as two words in a zsh script, `$cfg` does not word-split the way it would in bash,
# and deno receives "-c <path>" as a single argument with the space still in the filename.
#
# Usage: scripts/check-functions.sh
set -uo pipefail
cd "$(dirname "$0")/.."

failed=0
for dir in supabase/functions/*/; do
  name=$(basename "$dir")
  [ "$name" = "_shared" ] && continue
  [ -f "$dir/index.ts" ] || continue

  if [ -f "$dir/deno.json" ]; then
    output=$(deno check --config="$dir/deno.json" "$dir/index.ts" 2>&1)
  else
    output=$(deno check "$dir/index.ts" 2>&1)
  fi

  if printf '%s' "$output" | grep -q "^error\|ERROR"; then
    printf 'FAIL  %s\n' "$name"
    printf '%s\n' "$output" | sed 's/^/      /'
    failed=1
  else
    printf 'ok    %s\n' "$name"
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "---"
  echo "Some functions do not type-check."
  exit 1
fi
echo "---"
echo "All functions type-check."
