#!/system/bin/sh
MODDIR=${0%/*}/..
. "$MODDIR/lib/common.sh"

SYSROOT="${PAR_SYS_ROOT:-}"
LITTLE="$SYSROOT/sys/devices/system/cpu/cpu0/cpufreq"
BIG="$SYSROOT/sys/devices/system/cpu/cpu4/cpufreq"
GPU="$SYSROOT/sys/devices/platform/e82c0000.mali/devfreq/gpufreq"
EAS="$SYSROOT/sys/kernel/eas/boost"
DDR_LATENCY="$SYSROOT/sys/class/devfreq/ddrfreq_latency"

node_write() {
  path="$1"
  value="$2"
  [ -e "$path" ] && [ -w "$path" ] || return 0
  # Android mksh's printf may issue the value and trailing newline as separate
  # writes. Sysfs accepts the value, rejects the newline-only second write with
  # EINVAL, and makes a successful update look like a failure. Use the verified
  # single-write form and confirm the effective value.
  echo -n "$value" >"$path" 2>/dev/null || {
    log_msg "write failed: $path"
    return 1
  }
  actual_value="$(cat "$path" 2>/dev/null)"
  [ "$actual_value" = "$value" ] || {
    log_msg "write mismatch: $path requested=$value actual=$actual_value"
    return 1
  }
}

profile_value() {
  conf_get "$1" "$2"
}

apply_cluster() {
  prefix="$1"
  directory="$2"
  profile_file="$3"
  hardware_min="$(cat "$directory/cpuinfo_min_freq" 2>/dev/null)"

  [ -n "$hardware_min" ] && node_write "$directory/scaling_min_freq" "$hardware_min"
  node_write "$directory/scaling_max_freq" "$(profile_value "${prefix}_max" "$profile_file")"
  node_write "$directory/scaling_min_freq" "$(profile_value "${prefix}_min" "$profile_file")"

  interactive="$directory/interactive"
  node_write "$interactive/hispeed_freq" "$(profile_value "${prefix}_hispeed" "$profile_file")"
  node_write "$interactive/go_hispeed_load" "$(profile_value "${prefix}_go_hispeed_load" "$profile_file")"
  node_write "$interactive/target_loads" "$(profile_value "${prefix}_target_loads" "$profile_file")"
  node_write "$interactive/above_hispeed_delay" "$(profile_value "${prefix}_above_hispeed_delay" "$profile_file")"
  node_write "$interactive/min_sample_time" "$(profile_value "${prefix}_min_sample_time" "$profile_file")"
}

apply_profile() {
  profile="$1"
  allowed_profile "$profile" || return 1
  profile_file="$CONFIG_DIR/$profile.conf"
  [ -f "$profile_file" ] || return 1

  apply_cluster little "$LITTLE" "$profile_file"
  apply_cluster big "$BIG" "$profile_file"

  gpu_hardware_min="$(awk '{ for (i=1; i<=NF; i++) if (min == "" || $i < min) min=$i } END { print min }' "$GPU/available_frequencies" 2>/dev/null)"
  [ -n "$gpu_hardware_min" ] || gpu_hardware_min=103750000
  node_write "$GPU/min_freq" "$gpu_hardware_min"
  node_write "$GPU/max_freq" "$(profile_value gpu_max "$profile_file")"
  node_write "$GPU/min_freq" "$(profile_value gpu_min "$profile_file")"
  node_write "$EAS" "$(profile_value eas_boost "$profile_file")"

  # The active PAR kernel exposes Huawei's DDR latency vote device, not the
  # stock-ROM memlat_cpu4 class and not Qualcomm LLCC controls. A zero vote
  # releases the floor; performance uses a known Kirin 970 OPP below max DDR.
  node_write "$DDR_LATENCY/min_freq" "$(profile_value ddr_latency_min "$profile_file")"

  printf '%s\n' "$profile" >"$STATE_DIR/active-profile"
  log_msg "applied profile=$profile"
}

# UniPerf restores CPU/GPU limits captured by the vendor service before this
# module applies its persistent profile. Restore only the affected component
# after the daemon has observed that the finite event returned to that vendor
# baseline. Keeping this separate from apply_profile avoids rewriting governor,
# EAS, or unrelated cluster settings after every framework boost.
restore_uniperf_component() {
  profile="$1"
  component="$2"
  allowed_profile "$profile" || return 1
  profile_file="$CONFIG_DIR/$profile.conf"
  [ -f "$profile_file" ] || return 1

  case "$component" in
    big)
      desired_min="$(profile_value big_min "$profile_file")"
      desired_max="$(profile_value big_max "$profile_file")"
      current_min="$(cat "$BIG/scaling_min_freq" 2>/dev/null)"
      current_max="$(cat "$BIG/scaling_max_freq" 2>/dev/null)"
      if [ "$current_max" != "$desired_max" ]; then
        [ "$current_min" -le "$desired_max" ] 2>/dev/null || return 1
        node_write "$BIG/scaling_max_freq" "$desired_max"
      fi
      current_max="$(cat "$BIG/scaling_max_freq" 2>/dev/null)"
      [ "$desired_min" -le "$current_max" ] 2>/dev/null || return 1
      node_write "$BIG/scaling_min_freq" "$desired_min"
      ;;
    gpu)
      desired_min="$(profile_value gpu_min "$profile_file")"
      desired_max="$(profile_value gpu_max "$profile_file")"
      current_min="$(cat "$GPU/min_freq" 2>/dev/null)"
      current_max="$(cat "$GPU/max_freq" 2>/dev/null)"
      if [ "$current_max" != "$desired_max" ]; then
        [ "$current_min" -le "$desired_max" ] 2>/dev/null || return 1
        node_write "$GPU/max_freq" "$desired_max"
      fi
      current_max="$(cat "$GPU/max_freq" 2>/dev/null)"
      [ "$desired_min" -le "$current_max" ] 2>/dev/null || return 1
      node_write "$GPU/min_freq" "$desired_min"
      ;;
    *) return 2 ;;
  esac

  log_msg "restored UniPerf component=$component profile=$profile"
}

restore_stock_scheduler() {
  # These values are installed by Huawei's Kirin 970 init script and confirmed
  # against the nodes exposed by the current PAR kernel.
  node_write "$EAS" 0
  node_write "$DDR_LATENCY/min_freq" 0
  log_msg "restored stock EAS and DDR latency votes"
}

case "$1" in
  apply) apply_profile "$2" ;;
  restore-uniperf) restore_uniperf_component "$2" "$3" ;;
  restore-stock-scheduler) restore_stock_scheduler ;;
  *) printf 'usage: %s {apply <profile>|restore-uniperf <profile> <big|gpu>|restore-stock-scheduler}\n' "$0" >&2; exit 2 ;;
esac
