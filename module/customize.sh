#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 dere3046

SKIPUNZIP=1

DATA=${DATA:-/data/adb/phdroid}

command -v ui_print >/dev/null || ui_print() { echo "$1"; }
command -v abort >/dev/null || abort() { ui_print "$1"; exit 1; }

require_arm64() {
    [ "$ARCH" = arm64 ] || [ "$(uname -m)" = aarch64 ] || abort "! arm64 only"
}

# vendor kernels often drop the androidNN tag from uname -r; fall back to the
# launch API level, because the KMI follows the launch, not the OTA version
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

unpack_static() {
    unzip -o "$ZIPFILE" module.prop config.conf "*.sh" "webroot/*" \
        -d "$MODPATH" >&2 || abort "! unpack failed"
}

unpack_build() {
    mkdir -p "$MODPATH/bin"
    unzip -o "$ZIPFILE" "bin/$1/*" -d "$MODPATH" >&2 || abort "! unpack $1 failed"
    [ -d "$MODPATH/bin/$1" ] || abort "! no build for $1"
}

chmod_module() {
    chmod 0755 "$MODPATH" "$MODPATH/bin" "$MODPATH"/*.sh
    chmod 0644 "$MODPATH"/module.prop "$MODPATH"/config.conf
    find "$MODPATH"/bin -name '*.ko' -exec chmod 0644 {} \;
    # KernelSU's installer skips its own permission/secontext pass when
    # SKIPUNZIP=1, so the WebUI payload has to be set up here
    if [ -d "$MODPATH/webroot" ]; then
        chmod 0755 "$MODPATH/webroot"
        find "$MODPATH/webroot" -type f -exec chmod 0644 {} \;
    fi
    if command -v chcon >/dev/null 2>&1; then
        chcon -R u:object_r:system_file:s0 "$MODPATH" 2>/dev/null || true
    fi
}

main() {
    local kmi autoload
    require_arm64
    unpack_static

    kmi=$(detect_kmi)
    [ -n "$kmi" ] || abort "! cannot detect KMI from $(uname -r)"
    unpack_build "$kmi"

    mkdir -p "$DATA"
    rm -f "$DATA/blocked" "$DATA/insmod"

    # service.sh only insmods when this marker exists, so a fresh install has
    # to create it, otherwise the module never loads at all. autoload=0 opts out.
    autoload=$(sed -n 's/^autoload=//p' "$MODPATH/config.conf" 2>/dev/null | tail -n 1)
    [ "$autoload" = "0" ] || : > "$DATA/auto"

    chmod_module
    ui_print "- kmi    : $kmi"
    ui_print "- payload: $(ls "$MODPATH/bin/$kmi" | tr '\n' ' ')"
}

main
