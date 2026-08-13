#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
ROOT_VENDOR="$MODDIR/vendor"
SYSTEM_VENDOR="$MODDIR/system/vendor"
RELATIVE_TARGET=etc/xml/uniperf_config_cust.xml

# Framework events are opt-in. Keep the bridge off until post-mount verifies
# the effective OverlayFS file, its hash, and its SELinux label.
set_uniperf_bridge_enabled 0

# SukiSU may turn system/vendor into ../vendor during installation. Mountify
# scans and copies the system directory before mounting, so restore a physical
# system/vendor tree before the metamodule's metamount stage.
if [ -L "$SYSTEM_VENDOR" ] && [ -f "$ROOT_VENDOR/$RELATIVE_TARGET" ]; then
  rm -f "$SYSTEM_VENDOR"
  mkdir -p "$SYSTEM_VENDOR/etc/xml"
  cp -af "$ROOT_VENDOR/$RELATIVE_TARGET" "$SYSTEM_VENDOR/$RELATIVE_TARGET"
fi

if [ -f "$SYSTEM_VENDOR/$RELATIVE_TARGET" ]; then
  chown 0:0 "$SYSTEM_VENDOR/$RELATIVE_TARGET" 2>/dev/null
  chmod 0644 "$SYSTEM_VENDOR/$RELATIVE_TARGET" 2>/dev/null
  chcon u:object_r:vendor_configs_file:s0 "$SYSTEM_VENDOR/$RELATIVE_TARGET" 2>/dev/null
fi
