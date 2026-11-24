#!/bin/sh
# Reversible overlay: the original squashfs and executable remain intact.
set -eu
state=/mnt/config/pet-feeder-local
runtime=/run/pet-feeder-local
test -f "$state/enabled" || exit 0
release="$state"
if test -f "$state/active"; then
    digest=$(cat "$state/active")
    case "$digest" in *[!0-9a-f]*|'') exit 1;; esac
    test "${#digest}" -eq 64
    release="$state/releases/$digest"
fi
test -f "$release/pf_local.so" || exit 1
if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then exit 0; fi
set -- $(busybox sha256sum /usr/sbin/ak_tuya_ipc)
test "$1" = \
    f499431d38ed3cb8a4607ee870f06461e14ccb9f6f6387137b0ded2f5191a499
cd "$release"
busybox sha256sum -c module.sha256
LD_BIND_NOW=1 LD_PRELOAD="$release/pf_local.so" /bin/true
mkdir -p "$runtime"
cp /usr/sbin/ak_tuya_ipc "$runtime/ak_tuya_ipc"
cat > "$runtime/launcher" <<PF_LAUNCHER
#!/bin/sh
export PF_STATE_DIR=/mnt/config/pet-feeder-local
export LD_PRELOAD=$release/pf_local.so
exec /run/pet-feeder-local/ak_tuya_ipc > /dev/null 2>&1
PF_LAUNCHER
chmod 700 "$runtime/launcher"
# More specific than a DHCP-installed default route; the connected LAN wins.
busybox ip route add unreachable 0.0.0.0/1 2>/dev/null || true
busybox ip route add unreachable 128.0.0.0/1 2>/dev/null || true
mount --bind "$runtime/launcher" /usr/sbin/ak_tuya_ipc
