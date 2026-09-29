#!/usr/bin/env bash
set -euo pipefail

# Create a qcom-next worktree with the layered Glymur series applied:
# patches/kernel/upstream/qcom-next-acpi/*, upstream/qcom-next/* (generic
# fixes against qcom-next), patches/kernel/glymur-bringup/*, then
# patches/kernel/backports/* (one mainline fix touches a file the bring-up
# layer also changes).
# Usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo-root]

CLONE="${1:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
WORKTREE="${2:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
REPO="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BASE=e428097a36d210c50991063f17ee0848e9eb68a8

if [ -e "$WORKTREE" ]; then
    printf 'Refusing to reuse existing path: %s\n' "$WORKTREE" >&2
    exit 1
fi
git -C "$CLONE" worktree add -q --detach "$WORKTREE" "$BASE"
# git am needs a committer; a fresh install may have no identity configured.
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$(git config user.name || echo glymur-build)}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$(git config user.email || echo glymur-build@localhost)}"
git -C "$WORKTREE" am -q \
    "$REPO"/patches/kernel/upstream/qcom-next-acpi/*.patch \
    "$REPO"/patches/kernel/upstream/qcom-next/*.patch \
    "$REPO"/patches/kernel/glymur-bringup/*.patch \
    "$REPO"/patches/kernel/backports/*.patch
git -C "$WORKTREE" log --oneline "$BASE..HEAD"
