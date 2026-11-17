#!/bin/bash
# Says whether CI already passed on the code of commit $1, so the release workflow can skip
# testing it again. Exits 0 when a CI run (ci.yml, pushed to main) succeeded on $1 or on an
# ancestor whose only differences from $1 are in files CI ignores (IGNORED below, which must
# match paths-ignore in ci.yml): a release-notes commit on top of a tested one counts as
# tested. Waits for such a run that is still going, up to WAIT_MINUTES. Exits 1 in every
# other case, including any error, and the caller then runs the tests itself.
#
# Needs: full history (checkout fetch-depth 0), GH_TOKEN with actions: read, GITHUB_REPOSITORY.
set -uo pipefail
SHA=${1:?usage: ci-passed.sh <sha>}
WAIT_MINUTES=${WAIT_MINUTES:-30}
POLL_SECONDS=30
IGNORED=(':(exclude,glob)**/*.md' ':(exclude)docs' ':(exclude)LICENSE')

# The tagged commit, then each first-parent ancestor with the same code; the last one is the
# commit that changed it, the one CI ran on.
CANDIDATES=()
for C in $(git rev-list --first-parent --max-count=50 "$SHA"); do
    git diff --quiet "$C" "$SHA" -- . "${IGNORED[@]}" || break
    CANDIDATES+=("$C")
done
echo "Commits with the same code as ${SHA:0:7}: ${CANDIDATES[*]:0:20}"

DEADLINE=$(($(date +%s) + WAIT_MINUTES * 60))
while :; do
    PENDING=0
    for C in "${CANDIDATES[@]}"; do
        RUNS=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$C&event=push&branch=main" \
            --jq '.workflow_runs[] | "\(.status) \(.conclusion) \(.html_url)"') || { echo "Couldn't read CI's runs"; exit 1; }
        while read -r STATUS CONCLUSION URL; do
            [ -n "${STATUS:-}" ] || continue
            if [ "$STATUS" = completed ] && [ "$CONCLUSION" = success ]; then
                echo "CI passed on ${C:0:7}: $URL"
                exit 0
            fi
            [ "$STATUS" = completed ] || PENDING=1
        done <<< "$RUNS"
    done
    if [ "$PENDING" = 0 ]; then
        echo "No passing CI run for this code"
        exit 1
    fi
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
        echo "CI is still running after $WAIT_MINUTES minutes"
        exit 1
    fi
    echo "CI is still running on this code; checking again in $POLL_SECONDS s"
    sleep "$POLL_SECONDS"
done
