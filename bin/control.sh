#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/lib/common.sh"

PROFILE_KEYS="little_min little_max little_hispeed little_go_hispeed_load little_target_loads little_above_hispeed_delay little_min_sample_time big_min big_max big_hispeed big_go_hispeed_load big_target_loads big_above_hispeed_delay big_min_sample_time gpu_min gpu_max eas_boost stune_boost stune_prefer_idle ddr_latency_min"
LITTLE_FREQS="509000 1018000 1210000 1402000 1556000 1690000 1844000"
BIG_FREQS="682000 1018000 1210000 1364000 1498000 1652000 1863000 2093000 2362000"
GPU_FREQS="103750000 150909000 237143000 332000000 415000000 550000000 667000000 767000000"

in_list() {
  wanted="$1"
  shift
  for item in "$@"; do [ "$wanted" = "$item" ] && return 0; done
  return 1
}

valid_series() {
  printf '%s\n' "$1" | awk '
    NF < 1 { exit 1 }
    {
      for (i=1; i<=NF; i++) {
        if (i == 1) {
          if ($i !~ /^[0-9]+$/) exit 1
        } else {
          count=split($i, pair, ":")
          if (count != 2 || pair[1] !~ /^[0-9]+$/ || pair[2] !~ /^[0-9]+$/) exit 1
        }
      }
    }
  '
}

validate_profile_file() {
  file="$1"
  [ -s "$file" ] || return 1
  [ "$(wc -c <"$file")" -le 8192 ] || return 1
  [ "$(awk 'NF { count++ } END { print count+0 }' "$file")" -eq 20 ] || return 1

  for key in $PROFILE_KEYS; do
    [ "$(awk -F= -v wanted="$key" '$1 == wanted { count++ } END { print count+0 }' "$file")" -eq 1 ] || return 1
  done
  awk -F= -v allowed="$PROFILE_KEYS" '
    BEGIN { split(allowed, a, " "); for (i in a) ok[a[i]]=1 }
    NF && !($1 in ok) { exit 1 }
  ' "$file" || return 1

  little_min="$(conf_get little_min "$file")"
  little_max="$(conf_get little_max "$file")"
  little_hispeed="$(conf_get little_hispeed "$file")"
  big_min="$(conf_get big_min "$file")"
  big_max="$(conf_get big_max "$file")"
  big_hispeed="$(conf_get big_hispeed "$file")"
  gpu_min="$(conf_get gpu_min "$file")"
  gpu_max="$(conf_get gpu_max "$file")"
  eas_boost="$(conf_get eas_boost "$file")"
  stune_boost="$(conf_get stune_boost "$file")"
  stune_prefer_idle="$(conf_get stune_prefer_idle "$file")"
  ddr_latency_min="$(conf_get ddr_latency_min "$file")"

  in_list "$little_min" $LITTLE_FREQS && in_list "$little_max" $LITTLE_FREQS &&
    in_list "$little_hispeed" $LITTLE_FREQS || return 1
  in_list "$big_min" $BIG_FREQS && in_list "$big_max" $BIG_FREQS &&
    in_list "$big_hispeed" $BIG_FREQS || return 1
  in_list "$gpu_min" $GPU_FREQS && in_list "$gpu_max" $GPU_FREQS || return 1
  [ "$little_min" -le "$little_hispeed" ] && [ "$little_hispeed" -le "$little_max" ] || return 1
  [ "$big_min" -le "$big_hispeed" ] && [ "$big_hispeed" -le "$big_max" ] || return 1
  [ "$gpu_min" -le "$gpu_max" ] || return 1
  case "$eas_boost:$stune_prefer_idle" in
    [01]:[01]) ;;
    *) return 1 ;;
  esac
  is_int "$stune_boost" && [ "$stune_boost" -ge 0 ] && [ "$stune_boost" -le 100 ] || return 1
  in_list "$ddr_latency_min" 0 533000000 1244000000 1866000000 || return 1

  for key in little_go_hispeed_load big_go_hispeed_load; do
    value="$(conf_get "$key" "$file")"
    is_uint "$value" && [ "$value" -ge 1 ] && [ "$value" -le 100 ] || return 1
  done
  for key in little_min_sample_time big_min_sample_time; do
    value="$(conf_get "$key" "$file")"
    is_uint "$value" && [ "$value" -ge 1000 ] && [ "$value" -le 500000 ] || return 1
  done
  for key in little_target_loads little_above_hispeed_delay big_target_loads big_above_hispeed_delay; do
    valid_series "$(conf_get "$key" "$file")" || return 1
  done
}

save_profile() {
  profile="$1"
  payload="$2"
  allowed_profile "$profile" || return 2
  temp_file="$STATE_DIR/profile.$$.tmp"
  decode_payload "$payload" "$temp_file" || { rm -f "$temp_file"; return 2; }
  tr -d '\r' <"$temp_file" >"$temp_file.clean" && mv -f "$temp_file.clean" "$temp_file"
  validate_profile_file "$temp_file" || { rm -f "$temp_file"; return 2; }
  atomic_replace "$temp_file" "$CONFIG_DIR/$profile.conf" || { rm -f "$temp_file"; return 2; }
  rm -f "$temp_file"
  touch "$STATE_DIR/reload"
}

reset_profile() {
  requested="$1"
  case "$requested" in
    all) reset_profiles="powersave balanced performance" ;;
    *) allowed_profile "$requested" || return 2; reset_profiles="$requested" ;;
  esac

  for profile in $reset_profiles; do
    default_file="$CONFIG_DIR/defaults/$profile.conf"
    validate_profile_file "$default_file" || return 2
  done
  for profile in $reset_profiles; do
    atomic_replace "$CONFIG_DIR/defaults/$profile.conf" "$CONFIG_DIR/$profile.conf" || return 2
  done
  touch "$STATE_DIR/reload"
}

save_rules() {
  payload="$1"
  temp_file="$STATE_DIR/rules.$$.tmp"
  decode_payload "$payload" "$temp_file" || { rm -f "$temp_file"; return 2; }
  tr -d '\r' <"$temp_file" | sed '/^[[:space:]]*$/d' >"$temp_file.clean"
  mv -f "$temp_file.clean" "$temp_file"
  [ "$(wc -c <"$temp_file")" -le 65536 ] || { rm -f "$temp_file"; return 2; }
  awk -F'|' '
    NF != 2 { exit 1 }
    $1 !~ /^[A-Za-z0-9_][A-Za-z0-9._]*$/ { exit 1 }
    !($2 == "powersave" || $2 == "balanced" || $2 == "performance") { exit 1 }
    seen[$1]++ { exit 1 }
  ' "$temp_file" || { rm -f "$temp_file"; return 2; }
  atomic_replace "$temp_file" "$RULES_FILE" || { rm -f "$temp_file"; return 2; }
  rm -f "$temp_file"
  touch "$STATE_DIR/reload"
}

set_uniperf() {
  mode="$1"
  case "$mode" in balanced|performance) ;;
    *) return 2 ;;
  esac
  source_file="$CONFIG_DIR/uniperf-$mode.xml"
  target_file="$MODDIR/system/vendor/etc/xml/uniperf_config_cust.xml"
  [ -s "$source_file" ] || return 2
  set_uniperf_bridge_enabled 0
  atomic_replace "$source_file" "$target_file" || return 2
  chown 0:0 "$target_file" 2>/dev/null
  chmod 0644 "$target_file" 2>/dev/null
  chcon u:object_r:vendor_configs_file:s0 "$target_file" 2>/dev/null
  setting_set uniperf_mode "$mode"
  mark_reboot_required
}

print_status() {
  printf 'global_profile=%s\n' "$(conf_get global_profile "$SETTINGS_FILE")"
  printf 'dynamic_enabled=%s\n' "$(conf_get dynamic_enabled "$SETTINGS_FILE")"
  printf 'poll_interval=%s\n' "$(conf_get poll_interval "$SETTINGS_FILE")"
  printf 'thread_status=%s\n' "$(cat "$STATE_DIR/thread-status" 2>/dev/null)"
  printf 'uniperf_mode=%s\n' "$(conf_get uniperf_mode "$SETTINGS_FILE")"
  printf 'active_profile=%s\n' "$(cat "$STATE_DIR/active-profile" 2>/dev/null)"
  printf 'foreground_package=%s\n' "$(cat "$STATE_DIR/foreground-package" 2>/dev/null)"
  printf 'daemon_running=%s\n' "$([ -s "$STATE_DIR/daemon.pid" ] && daemon_pid_valid "$(cat "$STATE_DIR/daemon.pid")" && printf 1 || printf 0)"
  printf 'reboot_required=%s\n' "$([ -e "$STATE_DIR/reboot-required" ] && printf 1 || printf 0)"
  printf 'mounted=%s\n' "$(conf_get mounted "$STATE_DIR/mount-status.conf")"
  printf 'uniperf_bridge_enabled=%s\n' "$(getprop "$UNIPERF_BRIDGE_PROPERTY" 2>/dev/null)"
  printf 'mounted_context=%s\n' "$(conf_get context "$STATE_DIR/mount-status.conf")"
  printf 'mounted_at=%s\n' "$(conf_get mountpoint "$STATE_DIR/mount-status.conf")"
  printf 'mounted_fstype=%s\n' "$(conf_get fstype "$STATE_DIR/mount-status.conf")"
  printf 'rules_b64=%s\n' "$(base64 <"$RULES_FILE" 2>/dev/null | tr -d '\n')"
  for profile in powersave balanced performance; do
    printf 'profile_%s_b64=%s\n' "$profile" "$(base64 <"$CONFIG_DIR/$profile.conf" 2>/dev/null | tr -d '\n')"
  done
}

package_query() {
  if [ -x /system/bin/pm ]; then
    /system/bin/pm list packages "$@" 2>/dev/null
  elif command -v cmd >/dev/null 2>&1; then
    cmd package list packages "$@" 2>/dev/null
  else
    return 1
  fi
}

emit_packages() {
  system_flag="$1"
  awk -v system_flag="$system_flag" '
    sub(/^package:/, "") && $0 ~ /^[A-Za-z0-9_][A-Za-z0-9._]*$/ {
      print $0 "|" system_flag
    }
  '
}

list_apps() {
  third_party="$(package_query -3)"
  system_apps="$(package_query -s)"

  if [ -z "$third_party$system_apps" ]; then
    package_query | emit_packages 0 | sort -u
    return
  fi

  {
    printf '%s\n' "$third_party" | emit_packages 0
    printf '%s\n' "$system_apps" | emit_packages 1
  } | sort -t '|' -k 1,1 -u
}

case "$1" in
  status) print_status ;;
  list-apps) list_apps ;;
  set-global)
    allowed_profile "$2" || exit 2
    setting_set global_profile "$2" || exit 2
    touch "$STATE_DIR/reload"
    ;;
  set-dynamic)
    case "$2" in 0|1) setting_set dynamic_enabled "$2" ;; *) exit 2 ;; esac
    touch "$STATE_DIR/reload"
    ;;
  set-interval)
    is_uint "$2" && [ "$2" -ge 1 ] && [ "$2" -le 10 ] || exit 2
    setting_set poll_interval "$2" || exit 2
    touch "$STATE_DIR/reload"
    ;;
  save-profile) save_profile "$2" "$3" || exit 2 ;;
  reset-profile) reset_profile "$2" || exit 2 ;;
  save-rules) save_rules "$2" || exit 2 ;;
  set-uniperf) set_uniperf "$2" || exit 2 ;;
  apply)
    profile="$2"
    allowed_profile "$profile" || exit 2
    "$MODDIR/bin/engine.sh" apply "$profile"
    ;;
  *)
    printf 'usage: %s {status|list-apps|set-global|set-dynamic|set-interval|save-profile|reset-profile|save-rules|set-uniperf|apply}\n' "$0" >&2
    exit 2
    ;;
esac
