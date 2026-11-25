#!/usr/bin/env bash
# Push this chat's commits from the cloud sandbox.
#
# The sandbox registers gh as the git credential helper
# (credential.https://github.com.helper = !/usr/bin/gh auth git-credential) and
# ships the GitHub login in ~/.config/gh/hosts.yml, but not the gh binary - so
# every plain `git push` dies with
#
#   /usr/bin/gh auth git-credential get: 1: /usr/bin/gh: not found
#   fatal: could not read Username for 'https://github.com'
#
# This installs gh under $HOME (no root, nothing system-wide) and pushes with
# that copy as the helper, which then reads the stored login as it was meant to.
# The "/usr/bin/gh ... store: not found" lines a push still prints afterwards are
# harmless: the credential is found and the push has already succeeded.
#
# This lives in tools/, not src/, so it never travels inside the shipped .bat:
# tools/payload.py packs the .py and .bat files under src/ only.
#
#   tools/push-with-gh.sh             # HEAD -> origin main
#   tools/push-with-gh.sh some-branch # HEAD -> origin some-branch
#   GH_BIN=/path/to/gh tools/push-with-gh.sh   # reuse a gh already to hand
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

branch=${1:-main}

find_gh() {
    find "$HOME/tools" -maxdepth 3 -type f -name gh -perm -u+x 2>/dev/null \
        | sort -V | tail -1 || true
}

gh=${GH_BIN:-$(find_gh)}

if [ -z "$gh" ]; then
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) echo "no gh release for $(uname -m)" >&2; exit 1 ;;
    esac
    # The latest release's linux tarball, straight from GitHub's own API.
    url=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
          | grep -o "https://[^\"]*linux_${arch}\.tar\.gz" | head -1)
    if [ -z "$url" ]; then
        echo "could not find a gh release for linux/${arch}" >&2
        exit 1
    fi
    echo "installing $(basename "$url") into $HOME/tools"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/gh.tgz" "$url"
    mkdir -p "$HOME/tools"
    tar -xzf "$tmp/gh.tgz" -C "$HOME/tools"
    gh=$(find_gh)
    if [ -z "$gh" ]; then
        echo "gh was unpacked into $HOME/tools but no binary was found" >&2
        exit 1
    fi
fi

# The login comes from the sandbox's own gh config, never from this script. If
# it is missing, say so plainly rather than half-pushing.
if ! "$gh" auth status >/dev/null 2>&1; then
    echo "gh at $gh is not logged in (no usable token in ~/.config/gh)" >&2
    echo "A plain \`git push\` from a machine with your GitHub login will work." >&2
    exit 1
fi
echo "pushing as $("$gh" api user --jq .login) to origin/$branch"

git -c "credential.helper=!$gh auth git-credential" \
    push origin "HEAD:${branch}"

# What GitHub now says the branch is, so "pushed" is not taken on trust.
git ls-remote origin "refs/heads/${branch}"
