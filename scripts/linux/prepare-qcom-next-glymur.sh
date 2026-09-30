#!/usr/bin/env bash
set -euo pipefail

# qcom-next worktree with the layered series applied. See README.md.
# Usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo-root]

CLONE="${1:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
WORKTREE="${2:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
REPO="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BASE=6b4daa84523902fe715813633d47f1c568d2bcbc

if [ -e "$WORKTREE" ]; then
    printf 'Refusing to reuse existing path: %s\n' "$WORKTREE" >&2
    exit 1
fi
git -C "$CLONE" worktree add -q --detach "$WORKTREE" "$BASE"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$(git config user.name || echo glymur-build)}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$(git config user.email || echo glymur-build@localhost)}"
git -C "$WORKTREE" am -q \
    "$REPO"/patches/kernel/upstream/qcom-next-acpi/*.patch \
    "$REPO"/patches/kernel/upstream/qcom-next/*.patch \
    "$REPO"/patches/kernel/glymur-bringup/*.patch \
    "$REPO"/patches/kernel/backports/*.patch
git -C "$WORKTREE" log --oneline "$BASE..HEAD"
