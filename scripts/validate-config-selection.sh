#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <config.seed> <expanded .config>" >&2
	exit 2
fi

seed_file="$1"
expanded_config="$2"

if [[ ! -f "$seed_file" ]]; then
	echo "Seed config not found: $seed_file" >&2
	exit 2
fi

if [[ ! -f "$expanded_config" ]]; then
	echo "Expanded config not found: $expanded_config" >&2
	exit 2
fi

selected_count=0
missing_count=0
forbidden_count=0

while IFS= read -r selection; do
	((selected_count += 1))
	if ! grep -Fqx "$selection" "$expanded_config"; then
		echo "Selected config is missing: $selection" >&2
		((missing_count += 1))
	fi
done < <(
	tr -d '\r' <"$seed_file" |
		grep -E '^CONFIG_PACKAGE_.+=y$'
)

if ((selected_count == 0)); then
	echo "No enabled package selections found in seed config" >&2
	exit 2
fi

if ((missing_count > 0)); then
	echo "$missing_count selected package configs were dropped" >&2
	exit 1
fi

while IFS= read -r selection; do
	[[ -n "$selection" ]] || continue
	echo "Forbidden package config is enabled: $selection" >&2
	((forbidden_count += 1))
done < <(
	grep -E '^CONFIG_PACKAGE_luci-ssl.*=y$' "$expanded_config" || true
)

if ((forbidden_count > 0)); then
	echo "$forbidden_count forbidden package configs were enabled" >&2
	exit 1
fi

printf 'Validated %d selected package configs\n' "$selected_count"
