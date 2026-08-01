#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="${1:-$repo_root/package/openwrt-packages}"
helper_makefile="$package_root/luci-app-mwan3helper/Makefile"
helper_init="$package_root/luci-app-mwan3helper/root/etc/init.d/mwan3helper"

require_line() {
	local expected="$1"
	local file="$2"

	if [[ ! -f "$file" ]]; then
		echo "Missing imported package file: $file" >&2
		exit 1
	fi

	if ! grep -Fqx "$expected" "$file"; then
		echo "Imported package file is missing '$expected': $file" >&2
		exit 1
	fi
}

require_line 'PKG_RELEASE:=4' "$helper_makefile"
# shellcheck disable=SC2016
require_line 'include $(TOPDIR)/feeds/luci/luci.mk' "$helper_makefile"
require_line 'START=18' "$helper_init"

printf 'Validated migration package imports: %s\n' "$package_root"
