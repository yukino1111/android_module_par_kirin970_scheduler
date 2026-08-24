#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/lib/common.sh"

mkdir -p "$STATE_DIR"
if [ -s "$STATE_DIR/daemon.pid" ]; then
  old_pid="$(cat "$STATE_DIR/daemon.pid" 2>/dev/null)"
  daemon_pid_valid "$old_pid" && exit 0
  rm -f "$STATE_DIR/daemon.pid"
fi
printf '%s\n' "$$" >"$STATE_DIR/daemon.pid"
trap 'rm -f "$STATE_DIR/daemon.pid"; exit 0' TERM INT
trap 'rm -f "$STATE_DIR/daemon.pid"' EXIT

waited=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$waited" -lt 180 ]; do
  sleep 2
  waited=$((waited + 2))
done

foreground_package() {
  # AOSP 13 no longer includes focus state in the "windows" sub-dump on PAR.
  # "displays" is the smallest WindowManager sub-dump that still exposes
  # mFocusedApp, so avoid the substantially larger full dump on every poll.
  dumpsys window displays 2>/dev/null |
    awk '
      /mFocusedApp/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /\//) {
            value=$i
            sub(/^.*[ {]/, "", value)
            sub(/\/.*/, "", value)
            gsub(/[}]/, "", value)
            if (value ~ /^[A-Za-z0-9_][A-Za-z0-9._]*$/) { print value; exit }
          }
        }
      }
    '
}

rule_profile() {
  package_name="$1"
  [ -n "$package_name" ] || return 1
  while IFS='|' read -r rule_package rule_profile_value rule_extra; do
    [ -z "$rule_extra" ] || continue
    [ "$rule_package" = "$package_name" ] || continue
    allowed_profile "$rule_profile_value" || continue
    printf '%s\n' "$rule_profile_value"
    return 0
  done <"$RULES_FILE"
  return 1
}

load_runtime_config() {
  runtime_global_profile=balanced
  runtime_dynamic_enabled=0
  runtime_poll_interval=2

  while IFS='=' read -r setting_key setting_value; do
    case "$setting_key" in
      global_profile)
        allowed_profile "$setting_value" && runtime_global_profile="$setting_value"
        ;;
      dynamic_enabled)
        case "$setting_value" in 0|1) runtime_dynamic_enabled="$setting_value" ;; esac
        ;;
      poll_interval)
        if is_uint "$setting_value" &&
           [ "$setting_value" -ge 1 ] 2>/dev/null &&
           [ "$setting_value" -le 10 ] 2>/dev/null; then
          runtime_poll_interval="$setting_value"
        fi
        ;;
    esac
  done <"$SETTINGS_FILE"

  runtime_has_rules=0
  if [ "$runtime_dynamic_enabled" = "1" ]; then
    while IFS='|' read -r rule_package rule_profile_value rule_extra; do
      [ -z "$rule_extra" ] || continue
      case "$rule_package" in ''|*[!A-Za-z0-9._]*) continue ;; esac
      if allowed_profile "$rule_profile_value"; then
        runtime_has_rules=1
        break
      fi
    done <"$RULES_FILE"
  fi
}

uniperf_reset_value() {
  conf_get "$1" "$CONFIG_DIR/defaults/balanced.conf"
}

# The immutable balanced template matches the limits cached by Huawei's
# UniPerf service at boot. An active boost uses a different minimum frequency;
# wait until that minimum returns to the cached baseline before restoring the
# user's selected profile. This preserves finite boosts while repairing all
# three profiles after their expiry. Maximum-frequency restoration is gated by
# an exact vendor-baseline match so a thermal reduction is never raised.
reconcile_uniperf_limits() {
  profile="$1"
  profile_file="$CONFIG_DIR/$profile.conf"
  [ -f "$profile_file" ] || return 0

  big_dir=/sys/devices/system/cpu/cpu4/cpufreq
  gpu_dir=/sys/devices/platform/e82c0000.mali/devfreq/gpufreq

  desired_big_min="$(conf_get big_min "$profile_file")"
  desired_big_max="$(conf_get big_max "$profile_file")"
  reset_big_min="$(uniperf_reset_value big_min)"
  reset_big_max="$(uniperf_reset_value big_max)"
  actual_big_min="$(cat "$big_dir/scaling_min_freq" 2>/dev/null)"
  actual_big_max="$(cat "$big_dir/scaling_max_freq" 2>/dev/null)"
  if uniperf_component_needs_restore \
       "$actual_big_min" "$actual_big_max" \
       "$reset_big_min" "$reset_big_max" \
       "$desired_big_min" "$desired_big_max"; then
    "$MODDIR/bin/engine.sh" restore-uniperf "$profile" big
  fi

  desired_gpu_min="$(conf_get gpu_min "$profile_file")"
  desired_gpu_max="$(conf_get gpu_max "$profile_file")"
  reset_gpu_min="$(uniperf_reset_value gpu_min)"
  reset_gpu_max="$(uniperf_reset_value gpu_max)"
  actual_gpu_min="$(cat "$gpu_dir/min_freq" 2>/dev/null)"
  actual_gpu_max="$(cat "$gpu_dir/max_freq" 2>/dev/null)"
  if uniperf_component_needs_restore \
       "$actual_gpu_min" "$actual_gpu_max" \
       "$reset_gpu_min" "$reset_gpu_max" \
       "$desired_gpu_min" "$desired_gpu_max"; then
    "$MODDIR/bin/engine.sh" restore-uniperf "$profile" gpu
  fi
}

last_profile=
last_package=
load_runtime_config
force_apply=1
log_msg "daemon started"

while :; do
  if [ -e "$STATE_DIR/reload" ]; then
    rm -f "$STATE_DIR/reload"
    load_runtime_config
    force_apply=1
  fi

  selected_profile="$runtime_global_profile"
  package_name=

  if [ "$runtime_dynamic_enabled" = "1" ] && [ "$runtime_has_rules" = "1" ]; then
    package_name="$(foreground_package)"
    app_profile="$(rule_profile "$package_name")"
    allowed_profile "$app_profile" && selected_profile="$app_profile"
  fi

  if [ "$selected_profile" != "$last_profile" ] || [ "$force_apply" = "1" ]; then
    if "$MODDIR/bin/engine.sh" apply "$selected_profile"; then
      last_profile="$selected_profile"
    fi
    force_apply=0
  else
    reconcile_uniperf_limits "$selected_profile"
  fi

  if [ "$package_name" != "$last_package" ]; then
    printf '%s\n' "$package_name" >"$STATE_DIR/foreground-package"
    last_package="$package_name"
  fi

  sleep "$runtime_poll_interval"
done
