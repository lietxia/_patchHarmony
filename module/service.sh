#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 dere3046

MODDIR=${0%/*}
[ "$MODDIR" = "$0" ] && MODDIR=.

exec sh "$MODDIR/control.sh" boot
