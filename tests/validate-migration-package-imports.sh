#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-migration-package-imports.sh"
test_root="$(mktemp -d)"

cleanup() {
	rm -rf -- "$test_root"
}
trap cleanup EXIT

create_fixture() {
	local name="$1"
	local release="$2"
	local start="$3"
	local package_root="$test_root/$name"

	mkdir -p "$package_root/luci-app-mwan3helper/root/etc/init.d"
	# shellcheck disable=SC2016
	printf '%s\n' \
		"PKG_RELEASE:=$release" \
		'include $(TOPDIR)/feeds/luci/luci.mk' \
		> "$package_root/luci-app-mwan3helper/Makefile"
	printf 'START=%s\n' "$start" \
		> "$package_root/luci-app-mwan3helper/root/etc/init.d/mwan3helper"
}

create_fixture valid 4 18
create_fixture old_release 3 18
create_fixture late_start 4 60

"$validator" "$test_root/valid"

if "$validator" "$test_root/old_release" \
	>"$test_root/old_release.stdout" 2>"$test_root/old_release.stderr"; then
	echo "Validator accepted luci-app-mwan3helper release 3" >&2
	exit 1
fi
grep -Fqx \
	"Imported package file is missing 'PKG_RELEASE:=4': $test_root/old_release/luci-app-mwan3helper/Makefile" \
	"$test_root/old_release.stderr"

if "$validator" "$test_root/late_start" \
	>"$test_root/late_start.stdout" 2>"$test_root/late_start.stderr"; then
	echo "Validator accepted mwan3helper START=60" >&2
	exit 1
fi
grep -Fqx \
	"Imported package file is missing 'START=18': $test_root/late_start/luci-app-mwan3helper/root/etc/init.d/mwan3helper" \
	"$test_root/late_start.stderr"
