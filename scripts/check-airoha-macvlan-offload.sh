#!/bin/sh

set -eu

kernel_tree="${1:?usage: $0 /path/to/linux-kernel-tree}"
ppe_source="$kernel_tree/drivers/net/ethernet/airoha/airoha_ppe.c"

if [ ! -f "$ppe_source" ]; then
	printf 'missing Airoha PPE source: %s\n' "$ppe_source" >&2
	exit 2
fi

grep -Fq '#include <linux/if_macvlan.h>' "$ppe_source"
grep -Fq 'netif_is_macvlan(netdev)' "$ppe_source"
grep -Fq 'if (is_macvlan && type >= PPE_PKT_TYPE_IPV6_ROUTE_3T)' "$ppe_source"
grep -Fq 'netdev = macvlan_dev_real_dev(netdev);' "$ppe_source"

printf 'Airoha PPE IPv4 macvlan support and IPv6 safety guard are present.\n'
