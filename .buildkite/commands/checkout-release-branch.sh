#!/bin/bash -eu

# BUILDKITE_RELEASE_VERSION is passed as an environment variable from fastlane to Buildkite
# It must use the `BUILDKITE_` prefix to be passed to the agent due to how `hostmgr` works.
if [[ -z "${BUILDKITE_RELEASE_VERSION}" ]]; then
    echo "BUILDKITE_RELEASE_VERSION is not set."
    exit 1
fi

# Buildkite, by default, checks out a specific commit. For many release actions, we need to be
# on a release branch instead.
BRANCH_NAME="release/${BUILDKITE_RELEASE_VERSION}"
git fetch origin "$BRANCH_NAME"
git checkout "$BRANCH_NAME"
