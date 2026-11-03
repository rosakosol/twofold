#!/bin/sh
# Vercel's "Ignored Build Step" for the website, wired up in vercel.json as `ignoreCommand`.
#
# The repo holds the iOS app, the Supabase backend and the site, and every push to main used to
# rebuild and redeploy the site even when it touched only Swift or SQL. Vercel runs this from the
# project's Root Directory (site/) before building; exit 0 skips the build, exit 1 goes ahead.
#
# VERCEL_GIT_PREVIOUS_SHA is the commit of the last successful deployment of this branch. If
# nothing under site/ changed between it and this commit, there is nothing new to deploy.
#
# Every case this cannot judge builds, because a skipped deploy that should have shipped is worse
# than a redundant one:
#   - no previous SHA (the first deployment of a branch),
#   - the previous SHA is this commit (a manual redeploy, e.g. after changing an env var),
#   - the previous commit is not in Vercel's shallow clone, or git fails for any other reason.

set -u

previous="${VERCEL_GIT_PREVIOUS_SHA:-}"
current="${VERCEL_GIT_COMMIT_SHA:-HEAD}"

if [ -z "$previous" ]; then
  echo "No previous deployment to compare with: building."
  exit 1
fi

if [ "$previous" = "$current" ]; then
  echo "Redeploying the same commit: building."
  exit 1
fi

if ! git cat-file -e "${previous}^{commit}" 2>/dev/null; then
  # Vercel clones shallowly. Try to fetch the one commit before giving up and building.
  git fetch --quiet --depth=1 origin "$previous" 2>/dev/null || true
  if ! git cat-file -e "${previous}^{commit}" 2>/dev/null; then
    echo "Previous deployment ${previous} is not in this clone: building."
    exit 1
  fi
fi

# `.` is site/, the Root Directory, so this covers the app, its config, scripts and lockfile.
git diff --quiet "$previous" "$current" -- .
status=$?

if [ "$status" -eq 0 ]; then
  echo "Nothing under site/ changed since ${previous}: skipping the build."
  exit 0
fi

if [ "$status" -eq 1 ]; then
  echo "site/ changed since ${previous}: building."
  exit 1
fi

echo "git diff failed (status ${status}): building."
exit 1
