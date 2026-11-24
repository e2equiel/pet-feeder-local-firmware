#!/bin/sh
# Run on the feeder. Keep the private token and history for possible recovery.
set -eu
state=/mnt/config/pet-feeder-local
rm -f "$state/enabled"
if test -f /mnt/config/tmp_test.sh && grep -q 'PET_FEEDER_LOCAL_BOOT_HOOK' /mnt/config/tmp_test.sh; then
    rm /mnt/config/tmp_test.sh
fi
if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then
    umount /usr/sbin/ak_tuya_ipc
fi
busybox ip route del unreachable 0.0.0.0/1 2>/dev/null || true
busybox ip route del unreachable 128.0.0.0/1 2>/dev/null || true
pid=$(pidof ak_tuya_ipc || true)
if test -n "$pid"; then kill -TERM $pid; fi
sync
