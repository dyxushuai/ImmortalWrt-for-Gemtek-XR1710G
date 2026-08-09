#!/bin/sh
# Repro / regression check: local traffic via a forced client interface to 192.168.1.1
# Usage:
#   IFACE=en12 ./scripts/repro-gdm4-local-tx.sh
#   ROUTER=192.168.1.1 IFACE=en12 ./scripts/repro-gdm4-local-tx.sh
#
# Pass criteria (GDM4 OK): all provisioned assets return HTTP 200 and their
# expected minimum size. Missing required fixtures are failures; the optional
# concurrent fixture reports SKIP when it is not provisioned.
# Fail pattern (regressed): transfers stuck ~16k or partial large files.

set -eu

ROUTER="${ROUTER:-192.168.1.1}"
IFACE="${IFACE:-en12}"
TIMEOUT="${TIMEOUT:-15}"

curl_if() {
	curl --interface "$IFACE" -sS "$@"
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "missing command: $1" >&2
		exit 1
	}
}

need_cmd curl

echo "=== GDM4 local-TX repro ==="
echo "router=$ROUTER iface=$IFACE"
echo

echo "--- static 512k ---"
code=$(curl_if -o /tmp/gdm4-repro-512.bin -w '%{http_code}' --max-time "$TIMEOUT" \
	"http://$ROUTER/t-512k.bin" 2>/dev/null || echo 000)
sz=$(wc -c </tmp/gdm4-repro-512.bin 2>/dev/null || echo 0)
echo "t-512k.bin http=$code size=$sz (expect 524288 if file exists and path OK)"
if [ "$code" != "200" ] || [ "$sz" -lt 400000 ]; then
	echo "FAIL: static large file missing, unavailable, or truncated"
	exit 2
fi

echo "--- LuCI translations ---"
code=$(curl_if -o /tmp/gdm4-repro-zh.bin -w '%{http_code}' --max-time "$TIMEOUT" \
	"http://$ROUTER/cgi-bin/luci/admin/translations/zh-cn" 2>/dev/null || echo 000)
sz=$(wc -c </tmp/gdm4-repro-zh.bin 2>/dev/null || echo 0)
echo "translations http=$code size=$sz (OK ~350000; FAIL ~16000)"
if [ "$code" != "200" ] || [ "$sz" -lt 50000 ]; then
	echo "FAIL: translations missing, unavailable, or truncated ($sz bytes)"
	exit 3
fi
echo "PASS: translations full size"

echo "--- concurrent 4x 64k (if present) ---"
rm -f /tmp/gdm4-repro-c?.bin /tmp/gdm4-repro-c?.code
for i in 1 2 3 4; do
	(curl_if -o "/tmp/gdm4-repro-c$i.bin" -w '%{http_code}' --max-time 10 \
		"http://$ROUTER/t-64k.bin" >"/tmp/gdm4-repro-c$i.code" 2>/dev/null ||
		printf '000' >"/tmp/gdm4-repro-c$i.code") &
done
set +e
wait
set -e
ok=0
not_found=0
failed=0
for i in 1 2 3 4; do
	code=$(cat "/tmp/gdm4-repro-c$i.code" 2>/dev/null || echo 000)
	s=$(wc -c <"/tmp/gdm4-repro-c$i.bin" 2>/dev/null || echo 0)
	echo "  worker$i http=$code size=$s"
	if [ "$code" = "404" ]; then
		not_found=$((not_found + 1))
	elif [ "$code" != "200" ] || [ "$s" -ne 65536 ]; then
		failed=1
	else
		ok=$((ok + 1))
	fi
done
if [ "$not_found" -eq 4 ]; then
	echo "SKIP: t-64k.bin fixture is not provisioned"
elif [ "$not_found" -ne 0 ] || [ "$failed" -ne 0 ] || [ "$ok" -ne 4 ]; then
	echo "FAIL: one or more concurrent transfers missing or truncated"
	exit 4
else
	echo "PASS: concurrent transfers full"
fi

echo
if [ "$not_found" -eq 4 ]; then
	echo "DONE. Required translations + large static passed; concurrent fixture skipped."
else
	echo "DONE. Full translations + large static + concurrent transfers => GDM4 local TX OK."
fi
exit 0
