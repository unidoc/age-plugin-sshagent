# Justfile for age-plugin-sshagent — UniDoc's maintained fork of
# https://github.com/eszio/age-plugin-sshagent (full credit to the
# original author; see README.md).

default: build

# ── Build ────────────────────────────────────────────────────────────────

# Native build (host arch), version-stamped from version.txt.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p bin
    VERSION=$(cat version.txt | tr -d '[:space:]')
    CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=${VERSION}" -o bin/age-plugin-sshagent .

# Cross-build for Alpine arm64 hosts.
build-arm64:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p bin
    VERSION=$(cat version.txt | tr -d '[:space:]')
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-s -w -X main.version=${VERSION}" -o bin/age-plugin-sshagent-linux-arm64 .

# Cross-build for FreeBSD hosts.
build-freebsd arch="amd64":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p bin
    VERSION=$(cat version.txt | tr -d '[:space:]')
    CGO_ENABLED=0 GOOS=freebsd GOARCH={{arch}} go build -ldflags="-s -w -X main.version=${VERSION}" -o bin/age-plugin-sshagent-freebsd-{{arch}} .

# Cross-build for OpenBSD (amd64 only — lowest-priority target).
build-openbsd:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p bin
    VERSION=$(cat version.txt | tr -d '[:space:]')
    CGO_ENABLED=0 GOOS=openbsd GOARCH=amd64 go build -ldflags="-s -w -X main.version=${VERSION}" -o bin/age-plugin-sshagent-openbsd-amd64 .

# Cross-build for macOS — this tool's most common home is an
# operator's laptop (1Password's SSH agent is macOS/Windows-first),
# unlike incus-sync's server-only target set.
build-darwin arch="arm64":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p bin
    VERSION=$(cat version.txt | tr -d '[:space:]')
    CGO_ENABLED=0 GOOS=darwin GOARCH={{arch}} go build -ldflags="-s -w -X main.version=${VERSION}" -o bin/age-plugin-sshagent-darwin-{{arch}} .

# Build every target locally, for a quick manual smoke-test. Not the release
# path — see `release-pr`/`release` below for that.
build-all: build build-arm64 build-freebsd build-openbsd build-darwin
    @ls -la bin/

fmt:
    go fmt ./...
    go vet ./...

test:
    go test ./...

clean:
    rm -rf bin dist

# ── Release ──────────────────────────────────────────────────────────────
#
# Two-step, PR-based release flow:
#   1. just release-pr 0.2.0   → branch + version.txt bump + PR (review, CI)
#   2. merge the PR
#   3. just release 0.2.0      → verifies main carries 0.2.0, signs the tag,
#                                pushes — CI (goreleaser) publishes binaries,
#                                checksums and changelog to a GitHub Release.

# Step 1: open the version-bump PR. Only for an actual bump — if
# version.txt on main already carries VERSION (true for the very first
# release, since it ships pre-set), there is nothing to PR; go straight
# to `just release VERSION`.
release-pr VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    # Bare X.Y.Z only — the recipe adds the `v`. Rejects "v0.2.0" (→ vv0.2.0).
    [[ "{{VERSION}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version must be X.Y.Z (no leading v), got '{{VERSION}}'"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "✗ working tree not clean"; exit 1; }
    git fetch origin
    if [ "$(git show origin/main:version.txt | tr -d '[:space:]')" = "{{VERSION}}" ]; then
        echo "✗ version.txt on main is already {{VERSION}} — nothing to bump; run: just release {{VERSION}}"
        exit 1
    fi
    git ls-remote --exit-code --heads origin "release/v{{VERSION}}" >/dev/null 2>&1 && \
        { echo "✗ release/v{{VERSION}} already on origin — open the PR with: gh pr create --head release/v{{VERSION}} (or delete it: git push -d origin release/v{{VERSION}})"; exit 1; }
    trap 'git checkout main 2>/dev/null; git branch -D "release/v{{VERSION}}" 2>/dev/null || true' EXIT
    git checkout -b "release/v{{VERSION}}" origin/main
    echo "{{VERSION}}" > version.txt
    git add version.txt
    git commit -m "Release v{{VERSION}}"
    git push -u origin "release/v{{VERSION}}"
    trap - EXIT
    gh pr create --title "Release v{{VERSION}}" \
        --body "Bumps version.txt to {{VERSION}}. After merge: \`just release {{VERSION}}\` tags main and CI publishes the release." \
        || { echo "✗ branch pushed but PR creation failed — finish with: gh pr create --head release/v{{VERSION}}"; exit 1; }
    echo "✓ release PR opened — merge it, then run: just release {{VERSION}}"

# Local test-build of the release pipeline — same artifacts as a real
# release (dist/), nothing published. Requires goreleaser installed.
snapshot:
    goreleaser release --snapshot --clean --skip=validate
    @echo "✓ snapshot in dist/ — try: tar -xzf dist/*linux_amd64.tar.gz -C /tmp && /tmp/age-plugin-sshagent version"

# Step 2 (after the PR is merged): tag main and push the tag.
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{VERSION}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version must be X.Y.Z (no leading v), got '{{VERSION}}'"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "✗ working tree not clean"; exit 1; }
    git checkout main
    git pull --ff-only
    git fetch --tags origin  # catch remote-only tags the local repo hasn't seen
    [ "$(tr -d '[:space:]' < version.txt)" = "{{VERSION}}" ] || \
        { echo "✗ version.txt is '$(cat version.txt)' — merge the release PR first"; exit 1; }
    git rev-parse "v{{VERSION}}" >/dev/null 2>&1 && { echo "✗ tag v{{VERSION}} already exists"; exit 1; }
    git tag -s "v{{VERSION}}" -m "v{{VERSION}}"
    git push origin "v{{VERSION}}"
    echo "✓ v{{VERSION}} tagged — CI builds the release: gh run watch"
