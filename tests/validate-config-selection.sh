#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-config-selection.sh"
work_dir="$(mktemp -d)"

cleanup() {
	rm -rf -- "$work_dir"
}
trap cleanup EXIT

cat >"$work_dir/config.seed" <<'EOF'
CONFIG_PACKAGE_alpha=y
CONFIG_PACKAGE_beta=y
# CONFIG_PACKAGE_gamma is not set
EOF

cat >"$work_dir/config.missing" <<'EOF'
CONFIG_PACKAGE_alpha=y
# CONFIG_PACKAGE_beta is not set
# CONFIG_PACKAGE_gamma is not set
EOF

if "$validator" "$work_dir/config.seed" "$work_dir/config.missing" \
	>"$work_dir/missing.stdout" 2>"$work_dir/missing.stderr"; then
	echo "Expected missing package selection to fail validation" >&2
	exit 1
fi

grep -Fqx \
	"Selected config is missing: CONFIG_PACKAGE_beta=y" \
	"$work_dir/missing.stderr"

cat >"$work_dir/config.complete" <<'EOF'
CONFIG_PACKAGE_alpha=y
CONFIG_PACKAGE_beta=y
# CONFIG_PACKAGE_gamma is not set
EOF

"$validator" "$work_dir/config.seed" "$work_dir/config.complete"

cat >"$work_dir/config.forbidden" <<'EOF'
CONFIG_PACKAGE_alpha=y
CONFIG_PACKAGE_beta=y
CONFIG_PACKAGE_luci-ssl=y
# CONFIG_PACKAGE_gamma is not set
EOF

if "$validator" "$work_dir/config.seed" "$work_dir/config.forbidden" \
	>"$work_dir/forbidden.stdout" 2>"$work_dir/forbidden.stderr"; then
	echo "Expected forbidden package selection to fail validation" >&2
	exit 1
fi

grep -Fqx \
	"Forbidden package config is enabled: CONFIG_PACKAGE_luci-ssl=y" \
	"$work_dir/forbidden.stderr"
