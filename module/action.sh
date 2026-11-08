#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 dere3046
#
# KernelSU module Action button: Volume Up toggles load/unload, Volume Down
# toggles boot auto-load.

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.
BUSYBOX=${PHDROID_BUSYBOX:-/data/adb/ksu/bin/busybox}

printf '%s\n' 'Press Volume Up to toggle loading/unloading phDroid; press Volume Down to toggle boot auto-load.'
printf '%s\n' 'Waiting 30 seconds. If volume-key input is unavailable or no key is detected, Volume Up is selected by default.'

selection=up
if [ -x /system/bin/getevent ] && [ -x "$BUSYBOX" ]; then
    detected=$("$BUSYBOX" timeout 30 /system/bin/getevent -ql 2>/dev/null |
        "$BUSYBOX" awk '
            /KEY_VOLUMEUP[[:space:]]+DOWN/ { print "up"; exit }
            /KEY_VOLUMEDOWN[[:space:]]+DOWN/ { print "down"; exit }
        ')
    case "$detected" in
    up | down) selection=$detected ;;
    *) echo 'Volume-key input was unavailable; defaulting to Volume Up.' ;;
    esac
else
    echo 'Volume-key input is unavailable; defaulting to Volume Up.'
fi

case "$selection" in
down) sh "$MODDIR/control.sh" toggle-autoload ;;
up | "") sh "$MODDIR/control.sh" toggle-load ;;
*)
    echo "Unrecognized volume-key event: $selection" >&2
    exit 1
    ;;
esac
