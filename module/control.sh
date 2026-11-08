#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 dere3046
#
# phDroid control entry point. service.sh calls "boot" at late_start, the
# WebUI and the action button call the rest.

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.

DATA=${PHDROID_DATA_DIR:-/data/adb/phdroid}
CONF=$MODDIR/config.conf
AUTOLOAD_FILE=$DATA/auto
MARK=$DATA/insmod
BLOCK=$DATA/blocked
LOG=$DATA/phdroid.log
BUSYBOX=${PHDROID_BUSYBOX:-/data/adb/ksu/bin/busybox}
LOG_MAX=262144
LOG_TAIL=25

log_msg() {
    local size
    if [ -f "$LOG" ]; then
        size=$(wc -c < "$LOG" 2>/dev/null)
        [ "${size:-0}" -gt "$LOG_MAX" ] && rm -f "$LOG"
    fi
    printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
}

conf() {
    sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -n 1
}

api_tag() {
    case $1 in
    31 | 32) echo android12 ;;
    3[3-9] | 4[0-9]) echo "android$(($1 - 20))" ;;
    20[2-9][0-9][0-9][0-9]) echo "android$((${1%??} - 2009))" ;;
    esac
}

detect_kmi() {
    local release ver tag lvl
    release=$(uname -r)
    ver=$(printf '%s' "$release" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    tag=$(printf '%s' "$release" | sed -n 's/.*\(android[0-9][0-9]*\).*/\1/p')
    if [ -z "$tag" ]; then
        for p in ro.board.first_api_level ro.product.first_api_level; do
            lvl=$(getprop "$p" 2>/dev/null)
            [ -n "$lvl" ] || continue
            tag=$(api_tag "$lvl")
            [ -n "$tag" ] && break
        done
    fi
    [ -n "$ver" ] && [ -n "$tag" ] && echo "$tag-$ver"
}

# insmod/rmmod are busybox applets; KernelSU runs scripts with ASH_STANDALONE
# so they resolve, but fall back to an explicit busybox when they do not
insmod_ko() {
    local f=$1 bb
    shift
    if command -v insmod >/dev/null 2>&1; then
        insmod "$f" "$@" 2>&1
        return $?
    fi
    for bb in "$BUSYBOX" /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
        /data/adb/magisk/busybox "${MAGISKTMP:-/nonexistent}/busybox"; do
        [ -x "$bb" ] || continue
        "$bb" insmod "$f" "$@" 2>&1
        return $?
    done
    echo "insmod not found"
    return 127
}

rmmod_mod() {
    local m=$1 bb
    if command -v rmmod >/dev/null 2>&1; then
        rmmod "$m" 2>&1
        return $?
    fi
    for bb in "$BUSYBOX" /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
        /data/adb/magisk/busybox "${MAGISKTMP:-/nonexistent}/busybox"; do
        [ -x "$bb" ] || continue
        "$bb" rmmod "$m" 2>&1
        return $?
    done
    echo "rmmod not found"
    return 127
}

module_loaded() {
    [ -r /proc/modules ] && grep -q "^$1 " /proc/modules && return 0
    [ -d "/sys/module/$1" ] && return 0
    return 1
}

loaded_count() {
    local m n=0
    for m in $(conf modules); do
        module_loaded "$m" && n=$((n + 1))
    done
    echo "$n"
}

load_modules() {
    local m ko out rc
    for m in $(conf modules); do
        set -- "$MODDIR"/bin/*/"$m".ko
        ko=$1
        if [ ! -f "$ko" ]; then
            echo "missing $m.ko" >&2
            return 1
        fi
        if module_loaded "$m"; then
            echo "$m already loaded"
            continue
        fi
        out=$(insmod_ko "$ko" $(conf "$m"))
        rc=$?
        [ -n "$out" ] && echo "$out"
        [ "$rc" -eq 0 ] || return "$rc"
        echo "loaded $m"
    done
    return 0
}

unload_modules() {
    local m rev=""
    # unload in reverse order, the vendor fixups sit on top of the core module
    for m in $(conf modules); do
        rev="$m $rev"
    done
    for m in $rev; do
        if ! module_loaded "$m"; then
            echo "$m not loaded"
            continue
        fi
        rmmod_mod "$m" || return 1
        echo "unloaded $m"
    done
    return 0
}

set_autoload() {
    local value=$1
    case "$value" in
    1 | 0) ;;
    *) echo "Invalid auto-load value: $value" >&2; return 2 ;;
    esac
    mkdir -p "$DATA" || return 1
    if [ "$value" = 1 ]; then
        : > "$AUTOLOAD_FILE"
        echo "Boot auto-load enabled"
    else
        rm -f "$AUTOLOAD_FILE"
        echo "Boot auto-load disabled"
    fi
}

toggle_autoload() {
    if [ -f "$AUTOLOAD_FILE" ]; then
        set_autoload 0
    else
        set_autoload 1
    fi
}

toggle_load() {
    if [ "$(loaded_count)" -gt 0 ]; then
        unload_modules
    else
        load_modules
    fi
}

boot() {
    local rc
    mkdir -p "$DATA"

    [ -f "$AUTOLOAD_FILE" ] || {
        echo "Boot auto-load is disabled"
        return 0
    }

    if [ -f "$BLOCK" ]; then
        log_msg "blocked"
        return 0
    fi

    if [ -f "$MARK" ]; then
        mv -f "$MARK" "$BLOCK"
        log_msg "previous insmod never returned, blocked"
        return 0
    fi

    [ -n "$(conf modules)" ] || {
        log_msg "no modules declared"
        return 1
    }

    printf '%s\n' "$(conf modules)" > "$MARK"
    sync
    load_modules
    rc=$?
    rm -f "$MARK"
    sync

    if [ "$rc" -eq 0 ]; then
        log_msg "loaded $(conf modules)"
    else
        log_msg "install failed rc=$rc"
    fi
    return "$rc"
}

show_status() {
    local names total state autoload kmi
    names=$(conf modules)
    total=$(printf '%s\n' $names | wc -l)
    case "$(loaded_count)" in
    0) state=unloaded ;;
    *) [ "$(loaded_count)" -eq "$total" ] && state=loaded || state=partial ;;
    esac
    [ -f "$AUTOLOAD_FILE" ] && autoload=enabled || autoload=disabled
    kmi=$(detect_kmi 2>/dev/null) || kmi=unsupported
    echo "KMI=$kmi"
    echo "STATE=$state"
    echo "AUTOLOAD=$autoload"
    echo "LOADED=$(loaded_count)/$total"
    [ -f "$BLOCK" ] && echo "BLOCKED=yes" || echo "BLOCKED=no"
}

show_log() {
    if [ -f "$LOG" ]; then
        tail -n "$LOG_TAIL" "$LOG"
    else
        echo "no log yet"
    fi
}

command_name=${1:-status}
case "$command_name" in
status) show_status ;;
load | insmod) load_modules ;;
unload | rmmod) unload_modules ;;
toggle-load) toggle_load ;;
enable-autoload) set_autoload 1 ;;
disable-autoload) set_autoload 0 ;;
toggle-autoload) toggle_autoload ;;
boot) boot ;;
log) show_log ;;
detect-kmi) detect_kmi ;;
*)
    echo "Usage: $0 {status|load|unload|toggle-load|enable-autoload|disable-autoload|toggle-autoload|boot|log|detect-kmi}" >&2
    exit 2
    ;;
esac
