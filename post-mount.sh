#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
TARGET="${PAR_VENDOR_TARGET:-/vendor/etc/xml/uniperf_config_cust.xml}"
MOUNTINFO="${PAR_MOUNTINFO:-/proc/self/mountinfo}"
EXPECTED="$MODDIR/system/vendor/etc/xml/uniperf_config_cust.xml"

set_uniperf_bridge_enabled 0

mount_record="$(awk -v target="$TARGET" '
  {
    mountpoint=$5
    matches=(mountpoint == "/" || target == mountpoint || index(target, mountpoint "/") == 1)
    if (!matches || length(mountpoint) <= best_length) next
    fstype=""; source=""
    for (i=6; i<=NF; i++) {
      if ($i == "-") { fstype=$(i+1); source=$(i+2); break }
    }
    best_length=length(mountpoint)
    best_mountpoint=mountpoint
    best_fstype=fstype
    best_source=source
  }
  END { print best_mountpoint "|" best_fstype "|" best_source }
' "$MOUNTINFO" 2>/dev/null)"

# Android's mksh treats an unescaped `|` in parameter-expansion patterns as
# alternation. Split the record explicitly so a valid Mountify overlay is not
# misreported as an empty mountpoint/fstype.
mountpoint="$(printf '%s\n' "$mount_record" | awk -F'|' '{ print $1 }')"
fstype="$(printf '%s\n' "$mount_record" | awk -F'|' '{ print $2 }')"
source="$(printf '%s\n' "$mount_record" | awk -F'|' '{ print $3 }')"
context="$(ls -lZ "$TARGET" 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^u:object_r:/) { print $i; exit } }')"
target_hash="$(sha256sum "$TARGET" 2>/dev/null | awk '{print $1}')"
expected_hash="$(sha256sum "$EXPECTED" 2>/dev/null | awk '{print $1}')"
mounted=0

if [ "$fstype" = "overlay" ] && [ -n "$target_hash" ] &&
   [ "$target_hash" = "$expected_hash" ] &&
   [ "$context" = "u:object_r:vendor_configs_file:s0" ]; then
  mounted=1
fi

reboot_pending=0
if [ -e "$STATE_DIR/reboot-required" ]; then
  staged_boot_id="$(cat "$STATE_DIR/reboot-required" 2>/dev/null)"
  running_boot_id="$(current_boot_id)"
  if [ -n "$staged_boot_id" ] && [ -n "$running_boot_id" ] &&
     [ "$staged_boot_id" != "$running_boot_id" ]; then
    rm -f "$STATE_DIR/reboot-required"
  else
    reboot_pending=1
  fi
fi

bridge_enabled=0
if [ "$mounted" = 1 ] && [ "$reboot_pending" = 0 ] &&
   set_uniperf_bridge_enabled 1; then
  bridge_enabled=1
fi

{
  printf 'mounted=%s\n' "$mounted"
  printf 'bridge_enabled=%s\n' "$bridge_enabled"
  printf 'mountpoint=%s\n' "$mountpoint"
  printf 'fstype=%s\n' "$fstype"
  printf 'source=%s\n' "$source"
  printf 'context=%s\n' "$context"
  printf 'sha256=%s\n' "$target_hash"
  printf 'expected_sha256=%s\n' "$expected_hash"
} >"$MODDIR/state/mount-status.conf"
