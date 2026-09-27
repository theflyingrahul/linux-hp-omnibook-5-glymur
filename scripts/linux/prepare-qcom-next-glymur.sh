#!/usr/bin/env bash
set -euo pipefail

# Create a qcom-next worktree with the layered Glymur series applied:
# patches/kernel/upstream/qcom-next-acpi/*, then patches/kernel/glymur-bringup/*.
# Usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo-root]

CLONE="${1:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
WORKTREE="${2:?usage: prepare-qcom-next-glymur.sh <qcom-next-clone> <new-worktree> [repo]}"
REPO="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BASE=a47c4c5aa34b866136077d023d7c9e78d5a2225b

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
    "$REPO"/patches/kernel/glymur-bringup/*.patch
git -C "$WORKTREE" log --oneline "$BASE..HEAD"
