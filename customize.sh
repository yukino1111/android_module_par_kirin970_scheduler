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
ui_print "- Foreground source: kernel top-app cgroup (no dumpsys loop)"
ui_print "- UniPerf mode: balanced (PAR-compatible stock policy)"
ui_print "- No thermal, charging, vendor init, /data/system, or partition writes"

ACTIVE_MODULE="${PAR_ACTIVE_MODULE:-/data/adb/modules/par_kirin970_scheduler}"
if [ -d /data/adb/modules/asoul_affinity_opt ] &&
   [ ! -e /data/adb/modules/asoul_affinity_opt/disable ] &&
   [ ! -e /data/adb/modules/asoul_affinity_opt/remove ]; then
  ui_print "! A-SOUL Games Optimization is active"
  ui_print "! PAR per-thread placement will pause to prevent affinity conflicts"
fi
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

# Upgrade only the byte-for-byte v1.0.3 balanced template. Any user-edited
# balanced profile remains untouched and can opt into the new defaults through
# WebUI's restore action.
legacy_balanced="$MODPATH/config/legacy/balanced-v1.0.3.conf"
if [ -r "$legacy_balanced" ] && cmp -s "$MODPATH/config/balanced.conf" "$legacy_balanced"; then
  cp -f "$MODPATH/config/defaults/balanced.conf" "$MODPATH/config/balanced.conf" ||
    abort "! Cannot migrate the legacy balanced profile"
  ui_print "- Upgraded the unchanged v1.0.3 balanced profile for fluid daily use"
fi

legacy_settings="$MODPATH/config/legacy/settings-v1.0.3.conf"
if [ -r "$legacy_settings" ] && cmp -s "$MODPATH/config/settings.conf" "$legacy_settings"; then
  settings_temp="$MODPATH/config/settings.conf.migrate.$$"
  awk -F= '$1 == "poll_interval" { print "poll_interval=1"; next } { print }' \
    "$MODPATH/config/settings.conf" >"$settings_temp" || abort "! Cannot migrate top-app interval"
  mv -f "$settings_temp" "$MODPATH/config/settings.conf" || abort "! Cannot save top-app interval"
  ui_print "- Reduced the unchanged default top-app interval to 1 second"
fi

if grep -q '^thread_placement=' "$MODPATH/config/settings.conf" 2>/dev/null; then
  settings_temp="$MODPATH/config/settings.conf.thread.$$"
  awk -F= '$1 != "thread_placement" { print }' \
    "$MODPATH/config/settings.conf" >"$settings_temp" || abort "! Cannot remove legacy thread placement setting"
  mv -f "$settings_temp" "$MODPATH/config/settings.conf" || abort "! Cannot save global settings"
  ui_print "- Removed the obsolete foreground thread optimization switch"
fi

selected_uniperf_mode="$(sed -n 's/^uniperf_mode=//p' "$MODPATH/config/settings.conf" | head -n 1)"
case "$selected_uniperf_mode" in balanced|performance) ;;
  *) selected_uniperf_mode=balanced ;;
esac
cp -f "$MODPATH/config/uniperf-$selected_uniperf_mode.xml" \
  "$MODPATH/system/vendor/etc/xml/uniperf_config_cust.xml" ||
  abort "! Cannot stage PAR UniPerf $selected_uniperf_mode policy"

# Add newly introduced schedtune/DDR-latency keys from the immutable profile
# template. Kirin's global EAS boost node is a switch, not a 0..100 boost, so
# migrate legacy positive values to 1 and everything else unsupported to 0.
for profile_name in powersave balanced performance; do
  profile_file="$MODPATH/config/$profile_name.conf"
  default_file="$MODPATH/config/defaults/$profile_name.conf"
  profile_temp="$profile_file.migrate.$$"
  awk -F= '
    FNR == NR {
      defaults[$1]=$0
      order[++default_count]=$1
      next
    }
    $1 == "eas_boost" {
      print "eas_boost=" (($2 ~ /^[0-9]+$/ && $2 > 0) ? 1 : 0)
      seen[$1]=1
      next
    }
    { print; seen[$1]=1 }
    END {
      for (i=1; i<=default_count; i++) {
        key=order[i]
        if (!seen[key]) print defaults[key]
      }
    }
  ' "$default_file" "$profile_file" >"$profile_temp" || abort "! Cannot migrate $profile_name scheduler profile"
  mv -f "$profile_temp" "$profile_file" || abort "! Cannot save $profile_name scheduler profile"
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
set_perm "$MODPATH/lib/thread-scheduler.sh" 0 0 0644
set_perm "$MODPATH/config/settings.conf" 0 0 0644
set_perm "$MODPATH/config/powersave.conf" 0 0 0644
set_perm "$MODPATH/config/balanced.conf" 0 0 0644
set_perm "$MODPATH/config/performance.conf" 0 0 0644
set_perm "$MODPATH/config/defaults/powersave.conf" 0 0 0444
set_perm "$MODPATH/config/defaults/balanced.conf" 0 0 0444
set_perm "$MODPATH/config/defaults/performance.conf" 0 0 0444
set_perm "$MODPATH/config/legacy/balanced-v1.0.3.conf" 0 0 0444
set_perm "$MODPATH/config/legacy/settings-v1.0.3.conf" 0 0 0444
set_perm "$MODPATH/config/apps.conf" 0 0 0644
set_perm "$MODPATH/config/uniperf-balanced.xml" 0 0 0444
set_perm "$MODPATH/config/uniperf-performance.xml" 0 0 0444
set_perm "$MODPATH/system/vendor/etc/xml/uniperf_config_cust.xml" 0 0 0644 u:object_r:vendor_configs_file:s0

ui_print "- WebUI and Action button are available after reboot"
ui_print "- Mountify must remain enabled while this module is enabled"
ui_print "- Rebooting PAR may power it off; manually power it on if needed"
