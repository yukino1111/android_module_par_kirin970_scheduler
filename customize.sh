SKIPUNZIP=0

[ "$KSU" = "true" ] || abort "! This module requires KernelSU/SukiSU"
[ "$ARCH" = "arm64" ] || abort "! Unsupported architecture: $ARCH (arm64 required)"

metamodule_name="$KSU_METAMODULE"
if [ "$KSU_HAS_METAMODULE" != "true" ]; then
  if [ -d /data/adb/metamodule ] &&
     grep -Eq '^metamodule=(1|true)$' /data/adb/metamodule/module.prop 2>/dev/null; then
    metamodule_name="$(sed -n 's/^id=//p' /data/adb/metamodule/module.prop | head -n 1)"
  else
    abort "! A mounting metamodule is required; install Mountify first"
  fi
fi
[ -n "$metamodule_name" ] || metamodule_name=unknown

device="$(getprop ro.product.device 2>/dev/null)"
model="$(getprop ro.product.model 2>/dev/null)"
soc="$(getprop ro.board.platform 2>/dev/null)"

case "$device:$model:$soc" in
  *HWPAR*|*PAR-AL00*|*hi3670*) ;;
  *) abort "! Unsupported device: device=$device model=$model platform=$soc" ;;
esac

ui_print "- PAR Kirin 970 Scheduler"
ui_print "- Device: $model ($device), platform: $soc"
ui_print "- Android API: $API"
ui_print "- Mounting metamodule: $metamodule_name"
ui_print "- Profiles: powersave / balanced / performance"
ui_print "- Default profile: balanced"
ui_print "- UniPerf mode: balanced (PAR-compatible stock policy)"
ui_print "- No thermal, charging, vendor init, /data/system, or partition writes"

ACTIVE_MODULE=/data/adb/modules/par_kirin970_scheduler
mkdir -p "$MODPATH/config" "$MODPATH/state" "$MODPATH/system/vendor/etc/xml"
for uniperf_mode in balanced performance; do
  uniperf_policy="$MODPATH/config/uniperf-$uniperf_mode.xml"
  [ -r "$uniperf_policy" ] || abort "! Missing PAR UniPerf $uniperf_mode policy"
  grep -q '<policy version="1.0">' "$uniperf_policy" ||
    abort "! Invalid PAR UniPerf $uniperf_mode policy"
  grep -q '</policy>' "$uniperf_policy" ||
    abort "! Incomplete PAR UniPerf $uniperf_mode policy"
done

# Keep editable user choices across module updates. Factory templates live in
# config/defaults and are intentionally never replaced by these active files.
if [ -d "$ACTIVE_MODULE/config" ]; then
  for config_name in settings.conf apps.conf powersave.conf balanced.conf performance.conf; do
    [ -r "$ACTIVE_MODULE/config/$config_name" ] || continue
    cp -f "$ACTIVE_MODULE/config/$config_name" "$MODPATH/config/$config_name" ||
      abort "! Cannot preserve existing $config_name"
  done
  ui_print "- Preserved existing profiles, app rules, and global settings"
fi

selected_uniperf_mode="$(sed -n 's/^uniperf_mode=//p' "$MODPATH/config/settings.conf" | head -n 1)"
case "$selected_uniperf_mode" in balanced|performance) ;;
  *) selected_uniperf_mode=balanced ;;
esac
cp -f "$MODPATH/config/uniperf-$selected_uniperf_mode.xml" \
  "$MODPATH/system/vendor/etc/xml/uniperf_config_cust.xml" ||
  abort "! Cannot stage PAR UniPerf $selected_uniperf_mode policy"

# The Kirin 970 EAS store rejects negative values. Migrate only unsupported
# legacy/custom values while preserving every other profile parameter.
for profile_name in powersave balanced performance; do
  profile_file="$MODPATH/config/$profile_name.conf"
  profile_temp="$profile_file.migrate.$$"
  awk -F= '
    $1 == "eas_boost" && $2 ~ /^-/ { print "eas_boost=0"; next }
    { print }
  ' "$profile_file" >"$profile_temp" || abort "! Cannot migrate $profile_name EAS boost"
  mv -f "$profile_temp" "$profile_file" || abort "! Cannot save $profile_name EAS boost"
done

for script in \
  "$MODPATH/action.sh" \
  "$MODPATH/service.sh" \
  "$MODPATH/post-mount.sh" \
  "$MODPATH/bin/control.sh" \
  "$MODPATH/bin/daemon.sh" \
  "$MODPATH/bin/engine.sh"; do
  set_perm "$script" 0 0 0755
done

set_perm "$MODPATH/lib/common.sh" 0 0 0644
set_perm "$MODPATH/config/settings.conf" 0 0 0644
set_perm "$MODPATH/config/powersave.conf" 0 0 0644
set_perm "$MODPATH/config/balanced.conf" 0 0 0644
set_perm "$MODPATH/config/performance.conf" 0 0 0644
set_perm "$MODPATH/config/defaults/powersave.conf" 0 0 0444
set_perm "$MODPATH/config/defaults/balanced.conf" 0 0 0444
set_perm "$MODPATH/config/defaults/performance.conf" 0 0 0444
set_perm "$MODPATH/config/apps.conf" 0 0 0644
set_perm "$MODPATH/config/uniperf-balanced.xml" 0 0 0444
set_perm "$MODPATH/config/uniperf-performance.xml" 0 0 0444
set_perm "$MODPATH/system/vendor/etc/xml/uniperf_config_cust.xml" 0 0 0644 u:object_r:vendor_configs_file:s0

ui_print "- WebUI and Action button are available after reboot"
ui_print "- Mountify must remain enabled while this module is enabled"
ui_print "- Rebooting PAR may power it off; manually power it on if needed"
