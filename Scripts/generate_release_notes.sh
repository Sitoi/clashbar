#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <tag> <version> [output_path]" >&2
  exit 1
fi

tag="$1"
version="$2"
output_path="${3:-release.md}"
changelog_path="CHANGELOG.md"

if [[ ! -f "$changelog_path" ]]; then
  echo "Missing $changelog_path" >&2
  exit 1
fi

changelog_section="$(
  python3 - "$changelog_path" "$version" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    rf"^##\s+v?{re.escape(version)}\s*$\n(.*?)(?=^##\s+|\Z)",
    re.MULTILINE | re.DOTALL,
)
match = pattern.search(text)
if not match:
    sys.exit(1)
section = match.group(1).strip()
sys.stdout.write(section)
PY
)" || {
  echo "Failed to find release notes for version ${version} in ${changelog_path}" >&2
  exit 1
}

repo_url="https://github.com/${GITHUB_REPOSITORY}"
download_base="${repo_url}/releases/download/${tag}"

cat >"$output_path" <<EOF
## 更新内容

${changelog_section}

## 下载地址

- Apple Silicon（内置 Mihomo）: [ClashBar-${version}-apple-silicon.dmg](${download_base}/ClashBar-${version}-apple-silicon.dmg)
- Apple Silicon（无内核）: [ClashBar-${version}-apple-silicon-no-core.dmg](${download_base}/ClashBar-${version}-apple-silicon-no-core.dmg)
- Intel（内置 Mihomo）: [ClashBar-${version}-intel.dmg](${download_base}/ClashBar-${version}-intel.dmg)
- Intel（无内核）: [ClashBar-${version}-intel-no-core.dmg](${download_base}/ClashBar-${version}-intel-no-core.dmg)
EOF
