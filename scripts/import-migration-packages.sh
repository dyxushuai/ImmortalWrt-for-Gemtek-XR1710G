#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

LUCI_SOURCE_URL="https://github.com/coolsnowwolf/luci.git"
LUCI_SOURCE_COMMIT="3d589a69a52c6e84275dfdd8542f0cc39b2453f6"
CUSTOM_SOURCE_URL="https://github.com/dyxushuai/openwrt.git"
CUSTOM_SOURCE_COMMIT="f146fe750780e13aa66ce7fb65fc6acf07e2db7d"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/package/openwrt-packages"
work_root="$(mktemp -d)"

cleanup() {
	rm -rf -- "$work_root"
}
trap cleanup EXIT

if [[ -e "$package_root" ]]; then
	echo "Generated package directory already exists: $package_root" >&2
	exit 1
fi

mkdir -p "$package_root"

git clone --quiet --filter=blob:none --no-checkout "$LUCI_SOURCE_URL" "$work_root/luci"
git -C "$work_root/luci" sparse-checkout init --cone
git -C "$work_root/luci" sparse-checkout set applications/luci-app-mwan3helper
git -C "$work_root/luci" checkout --quiet --detach "$LUCI_SOURCE_COMMIT"
cp -a \
	"$work_root/luci/applications/luci-app-mwan3helper" \
	"$package_root/luci-app-mwan3helper"

helper_makefile="$package_root/luci-app-mwan3helper/Makefile"
helper_init="$package_root/luci-app-mwan3helper/root/etc/init.d/mwan3helper"
grep -qx 'PKG_RELEASE:=3' "$helper_makefile"
sed -i.bak 's/^PKG_RELEASE:=3$/PKG_RELEASE:=4/' "$helper_makefile"
rm -f -- "$helper_makefile.bak"
grep -qx 'PKG_RELEASE:=4' "$helper_makefile"
# shellcheck disable=SC2016
sed -i.bak \
	's#include ../../luci.mk#include $(TOPDIR)/feeds/luci/luci.mk#' \
	"$helper_makefile"
rm -f -- "$helper_makefile.bak"
# shellcheck disable=SC2016
grep -Fqx 'include $(TOPDIR)/feeds/luci/luci.mk' "$helper_makefile"

# mwan3 rules reference helper-provided ipsets, so create them before mwan3
# and firewall start at priority 19.
grep -qx 'START=60' "$helper_init"
sed -i.bak 's/^START=60$/START=18/' "$helper_init"
rm -f -- "$helper_init.bak"
grep -qx 'START=18' "$helper_init"

git clone --quiet --filter=blob:none --no-checkout "$CUSTOM_SOURCE_URL" "$work_root/custom"
git -C "$work_root/custom" sparse-checkout init --cone
git -C "$work_root/custom" sparse-checkout set packages/net/pdnsd-alt
git -C "$work_root/custom" checkout --quiet --detach "$CUSTOM_SOURCE_COMMIT"
cp -a \
	"$work_root/custom/packages/net/pdnsd-alt" \
	"$package_root/pdnsd-alt"

"$repo_root/scripts/validate-migration-package-imports.sh" "$package_root"

printf 'Imported migration packages:\n'
printf '  luci-app-mwan3helper %s\n' "$LUCI_SOURCE_COMMIT"
printf '  pdnsd-alt %s\n' "$CUSTOM_SOURCE_COMMIT"
