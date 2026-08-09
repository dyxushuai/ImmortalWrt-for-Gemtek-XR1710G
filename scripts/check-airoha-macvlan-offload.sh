#!/bin/sh

set -eu

kernel_tree="${1:?usage: $0 /path/to/linux-kernel-tree}"
ppe_source="$kernel_tree/drivers/net/ethernet/airoha/airoha_ppe.c"
eth_source="$kernel_tree/drivers/net/ethernet/airoha/airoha_eth.c"
eth_header="$kernel_tree/drivers/net/ethernet/airoha/airoha_eth.h"

for source in "$ppe_source" "$eth_source" "$eth_header"; do
	if [ ! -f "$source" ]; then
		printf 'missing Airoha source: %s\n' "$source" >&2
		exit 2
	fi
done

python3 - "$ppe_source" "$eth_source" "$eth_header" <<'PY'
import re
import sys

# Avoid PEP 585 generics (tuple[str, str]) so Python 3.8 hosts still work.


def extract_fn_body(src, pattern, label):
    m = re.search(pattern, src, re.S)
    if not m:
        sys.stderr.write("could not locate %s\n" % label)
        sys.exit(1)
    brace_at = m.end() - 1
    if brace_at < 0 or src[brace_at] != "{":
        sys.stderr.write("%s: expected opening brace\n" % label)
        sys.exit(1)
    depth = 0
    end = None
    for i in range(brace_at, len(src)):
        ch = src[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        sys.stderr.write("unbalanced braces in %s\n" % label)
        sys.exit(1)
    return src[brace_at : end + 1], src[: m.start()] + src[end + 1 :]


def code_line(line):
    code = line.split("/*", 1)[0]
    if "//" in code:
        code = code.split("//", 1)[0]
    return code


ppe_path, eth_path, hdr_path = sys.argv[1:4]
ppe = open(ppe_path, encoding="utf-8", errors="replace").read()
eth = open(eth_path, encoding="utf-8", errors="replace").read()
hdr = open(hdr_path, encoding="utf-8", errors="replace").read()

if "#include <linux/if_macvlan.h>" not in ppe:
    sys.stderr.write("missing if_macvlan.h include\n")
    sys.exit(1)

ppe_body, _ = extract_fn_body(
    ppe,
    r"static int\s+airoha_ppe_foe_entry_prepare\s*\([^)]*\)\s*\{",
    "airoha_ppe_foe_entry_prepare",
)
ipv6 = ppe_body.find("type >= PPE_PKT_TYPE_IPV6_ROUTE_3T")
unwrap = ppe_body.find("macvlan_dev_real_dev(netdev)")
if ipv6 < 0:
    sys.stderr.write("missing IPv6 macvlan reject in foe_entry_prepare\n")
    sys.exit(1)
if unwrap < 0:
    sys.stderr.write("missing macvlan_dev_real_dev unwrap in foe_entry_prepare\n")
    sys.exit(1)
if ipv6 > unwrap:
    sys.stderr.write("IPv6 macvlan reject must appear before macvlan unwrap\n")
    sys.exit(1)
if "netif_is_macvlan(netdev)" not in ppe_body:
    sys.stderr.write("missing netif_is_macvlan in foe_entry_prepare\n")
    sys.exit(1)
# Require stacked unwrap (do/while or while loop), not a single-level call.
if not re.search(
    r"do\s*\{[^}]*macvlan_dev_real_dev\s*\(\s*netdev\s*\)[^}]*\}\s*while\s*\([^;]*netif_is_macvlan\s*\(\s*netdev\s*\)",
    ppe_body,
    re.S,
) and not re.search(
    r"while\s*\([^;]*netif_is_macvlan\s*\(\s*netdev\s*\)[^)]*\)\s*"
    r"(?:\{[^}]*macvlan_dev_real_dev\s*\(\s*netdev\s*\)|"
    r"macvlan_dev_real_dev\s*\(\s*netdev\s*\))",
    ppe_body,
    re.S,
):
    sys.stderr.write(
        "stacked macvlan unwrap loop (do/while or while) is required\n"
    )
    sys.exit(1)

eth_required = [
    "__airoha_update_fe_mac_range(struct airoha_eth *eth,",
    "lockdep_assert_held(&eth->mac_lock);",
    "airoha_mac_range_include",
    "airoha_gdm_dev_in_mac_role",
    "dev->uc_valid = upper.valid;",
    "ether_addr_copy(dev->hw_addr, addr);",
    "spin_lock_bh(&eth->mac_lock);",
    ".ndo_set_rx_mode",
    "Keep LAN FE programming physical-only",
    "fe_mac_prog",
    "keeping the previous hardware range",
    "software receive fallback",
    # 920-18: refuse unsafe upper FE programming (cross-OUI / sparse)
    "keep physical FE range, upper uses software receive",
    "same_oui",
]
for token in eth_required:
    if token not in eth:
        sys.stderr.write("missing in airoha_eth.c: %s\n" % token)
        sys.exit(1)

# Must not still prefer unsafe upper-only FE ranges.
if "physical addresses leave the hardware MAC range" in eth:
    sys.stderr.write(
        "airoha_eth.c still demotes physical FE range for cross-OUI upper "
        "(apply 920-18 reject-sparse/cross-oui patch)\n"
    )
    sys.exit(1)
if "unrelated addresses may reach PPE lookup" in eth:
    sys.stderr.write(
        "airoha_eth.c still programs sparse upper FE ranges with only a warning "
        "(apply 920-18 reject-sparse/cross-oui patch)\n"
    )
    sys.exit(1)

# 920-18 must fail closed in both unsafe upper-range cases. Token presence
# alone is not enough: a warning without the physical fallback is a regression.
if not re.search(
    r"if\s*\(\s*!same_oui\s*\)\s*\{.*?selected\s*=\s*physical\s*;.*?\}\s*else\s*\{",
    eth,
    re.S,
):
    sys.stderr.write("cross-OUI upper range does not select physical FE fallback\n")
    sys.exit(1)
if not re.search(
    r"if\s*\(\s*span\s*>\s*selected\.count.*?"
    r"span\s*>\s*selected\.count\s*\*\s*8.*?"
    r"span\s*>\s*selected\.count\s*\+\s*64.*?"
    r"selected\s*=\s*physical\s*;",
    eth,
    re.S,
):
    sys.stderr.write("sparse upper range does not select physical FE fallback\n")
    sys.exit(1)

if "IFF_UNICAST_FLT" in eth:
    sys.stderr.write(
        "Airoha must retain the unicast-promiscuous software fallback\n"
    )
    sys.exit(1)

set_mac_body, _ = extract_fn_body(
    eth,
    r"static int\s+airoha_set_macaddr\s*\([^)]*\)\s*\{",
    "airoha_set_macaddr",
)
if "__airoha_update_fe_mac_range(eth, dev, lan)" not in set_mac_body:
    sys.stderr.write("airoha_set_macaddr bypasses the combined FE MAC updater\n")
    sys.exit(1)
for line in set_mac_body.splitlines():
    code = code_line(line)
    if "REG_FE_LAN_MAC_H" in code or "REG_FE_WAN_MAC_H" in code:
        sys.stderr.write(
            "airoha_set_macaddr still writes FE MAC registers directly\n"
        )
        sys.exit(1)

set_rx_body, _ = extract_fn_body(
    eth,
    r"static void\s+airoha_dev_set_rx_mode\s*\([^)]*\)\s*\{",
    "airoha_dev_set_rx_mode",
)
if "netif_addr_lock" in set_rx_body:
    sys.stderr.write(
        "airoha_dev_set_rx_mode must not reacquire its address-list lock\n"
    )
    sys.exit(1)

fe_body, fe_outside = extract_fn_body(
    eth,
    r"static bool\s+__airoha_update_fe_mac_range\s*\([^;]*?\)\s*\{",
    "__airoha_update_fe_mac_range",
)
for token in ("REG_FE_WAN_MAC_H", "REG_FE_LAN_MAC_H"):
    if token not in fe_body:
        sys.stderr.write(
            "__airoha_update_fe_mac_range does not program %s\n" % token
        )
        sys.exit(1)
for line in fe_outside.splitlines():
    code = code_line(line)
    for token in ("REG_FE_WAN_MAC_H", "REG_FE_LAN_MAC_H"):
        if token in code:
            sys.stderr.write(
                "%s used outside __airoha_update_fe_mac_range\n" % token
            )
            sys.exit(1)

lan_guard = fe_body.find("if (lan)")
upper_merge = fe_body.find("if (dev->uc_conflict)")
if lan_guard < 0 or upper_merge < 0 or lan_guard > upper_merge:
    sys.stderr.write(
        "LAN must remain physical-only before upper UC aggregation\n"
    )
    sys.exit(1)

hdr_required = [
    "u32 uc_count;",
    "u8 uc_prefix[3];",
    "u8 hw_addr[ETH_ALEN];",
    "spinlock_t mac_lock;",
    "fe_mac_prog[2]",
]
for token in hdr_required:
    if token not in hdr:
        sys.stderr.write("missing in airoha_eth.h: %s\n" % token)
        sys.exit(1)

print(
    "Airoha IPv4 macvlan PPE rules, WAN upper-MAC registration, "
    "physical-only LAN behavior, sparse/cross-OUI FE reject, "
    "software fallback, locking, and IPv6 guard are present."
)
PY
