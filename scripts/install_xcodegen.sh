#!/usr/bin/env bash
set -euo pipefail

readonly XCODEGEN_VERSION="2.46.0"
readonly XCODEGEN_SHA256="4D9E34B62172D645EED6457CAC13FC222569974098EF4EE9C3368BEDF0196806"
readonly XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"

temporary_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
install_root="$(mktemp -d "${temporary_root%/}/xcodegen-${XCODEGEN_VERSION}.XXXXXX")"
archive_path="$install_root/xcodegen.zip"

curl \
  --fail \
  --location \
  --proto '=https' \
  --proto-redir '=https' \
  --retry 3 \
  --show-error \
  --silent \
  --tlsv1.2 \
  --output "$archive_path" \
  "$XCODEGEN_URL"

actual_sha256="$(shasum -a 256 "$archive_path" | awk '{ print toupper($1) }')"
if [[ "$actual_sha256" != "$XCODEGEN_SHA256" ]]; then
  echo "XcodeGen ${XCODEGEN_VERSION} checksum mismatch." >&2
  echo "Expected: $XCODEGEN_SHA256" >&2
  echo "Actual:   $actual_sha256" >&2
  exit 1
fi

unzip -q "$archive_path" -d "$install_root"
xcodegen_bin="$install_root/xcodegen/bin/xcodegen"
if [[ ! -x "$xcodegen_bin" ]]; then
  echo "Verified XcodeGen archive did not contain xcodegen/bin/xcodegen." >&2
  exit 1
fi

version_output="$("$xcodegen_bin" --version)"
if [[ "$version_output" != *"$XCODEGEN_VERSION"* ]]; then
  echo "Verified XcodeGen binary reported an unexpected version: $version_output" >&2
  exit 1
fi

if [[ -z "${GITHUB_PATH:-}" ]]; then
  echo "GITHUB_PATH is unavailable; cannot expose the pinned XcodeGen binary." >&2
  exit 1
fi
printf '%s\n' "$(dirname "$xcodegen_bin")" >> "$GITHUB_PATH"

echo "Installed XcodeGen ${XCODEGEN_VERSION} from the checksum-pinned official release archive."
