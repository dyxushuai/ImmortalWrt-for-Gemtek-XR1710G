#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$repo_root/bin/targets/airoha/an7581"
package_dir="$repo_root/bin/packages/aarch64_cortex-a53/base"

"$repo_root/scripts/validate-config-selection.sh" \
	"$repo_root/config.seed" \
	"$repo_root/.config"

firmware=("$target_dir"/*gemtek_xr1710g-ubi*squashfs-sysupgrade.itb)
manifests=("$target_dir"/*gemtek_xr1710g-ubi.manifest)

if [[ ${#firmware[@]} -ne 1 || ! -f "${firmware[0]}" ]]; then
	echo "Expected exactly one XR1710G sysupgrade image" >&2
	exit 1
fi

if [[ ${#manifests[@]} -ne 1 || ! -f "${manifests[0]}" ]]; then
	echo "Expected exactly one XR1710G package manifest" >&2
	exit 1
fi

required_packages=(
	ddns-go
	ddns-scripts
	ddns-scripts-aliyun
	ddns-scripts-cloudflare
	ddns-scripts-dnspod
	ddns-scripts-services
	dropbear
	haproxy
	htop
	kmod-macvlan
	kmod-nft-offload
	luci-app-airoha-fancontrol
	luci-app-airoha-flowsense
	luci-app-airoha-npu
	luci-app-ddns
	luci-app-ddns-go
	luci-app-mwan3
	luci-app-mwan3helper
	luci-i18n-airoha-fancontrol-zh-cn
	luci-i18n-airoha-flowsense-zh-cn
	luci-i18n-airoha-npu-zh-cn
	luci-i18n-ddns-go-zh-cn
	luci-i18n-ddns-zh-cn
	luci-i18n-mwan3-zh-cn
	luci-i18n-mwan3helper-zh-cn
	mwan3
	pdnsd-alt
	ppp-mod-pppoe
	uhttpd
)

for package in "${required_packages[@]}"; do
	if ! grep -Fq "$package - " "${manifests[0]}"; then
		echo "Required package is missing from the firmware: $package" >&2
		exit 1
	fi
done

for package in \
	openssh-server \
	openssh-sftp-server \
	luci-ssl \
	luci-ssl-openssl; do
	if grep -Fq "$package - " "${manifests[0]}"; then
		echo "Excluded package is present in the firmware: $package" >&2
		exit 1
	fi
done

for pattern in \
	'luci-app-mwan3helper-*.apk' \
	'luci-i18n-mwan3helper-zh-cn-*.apk' \
	'pdnsd-alt-*.apk'; do
	mapfile -t matches < <(
		find "$package_dir" -maxdepth 1 -type f -name "$pattern" -print
	)
	if [[ ${#matches[@]} -ne 1 || ! -f "${matches[0]}" ]]; then
		echo "Expected exactly one package matching $pattern" >&2
		exit 1
	fi
done

test -f "$target_dir/sha256sums"
(
	cd "$target_dir"
	sha256sum --check sha256sums
)

printf 'Validated firmware: %s\n' "${firmware[0]}"
printf 'Validated manifest: %s\n' "${manifests[0]}"
