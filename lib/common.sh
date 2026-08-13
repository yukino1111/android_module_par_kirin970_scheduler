#!/system/bin/sh

if [ -z "$MODDIR" ]; then
  MODDIR="${0%/*}/.."
fi
normalized_moddir="$(cd "$MODDIR" 2>/dev/null && pwd)"
[ -n "$normalized_moddir" ] && MODDIR="$normalized_moddir"

CONFIG_DIR="$MODDIR/config"
STATE_DIR="$MODDIR/state"
SETTINGS_FILE="$CONFIG_DIR/settings.conf"
CUSTOM_FILE="$CONFIG_DIR/custom.conf"
RULES_FILE="$CONFIG_DIR/apps.conf"
UNIPERF_BRIDGE_PROPERTY=sys.par.uniperf.enabled

mkdir -p "$CONFIG_DIR" "$STATE_DIR"

log_msg() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >>"$STATE_DIR/daemon.log"
}

set_uniperf_bridge_enabled() {
  requested_value="$1"
  case "$requested_value" in 0|1) ;; *) return 2 ;; esac

  for resetprop_bin in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/magisk/resetprop \
    /data/adb/ap/bin/resetprop; do
    [ -x "$resetprop_bin" ] || continue
    "$resetprop_bin" "$UNIPERF_BRIDGE_PROPERTY" "$requested_value" >/dev/null 2>&1 || continue
    [ "$(getprop "$UNIPERF_BRIDGE_PROPERTY" 2>/dev/null)" = "$requested_value" ] && return 0
  done

  if command -v resetprop >/dev/null 2>&1; then
    resetprop "$UNIPERF_BRIDGE_PROPERTY" "$requested_value" >/dev/null 2>&1
  else
    setprop "$UNIPERF_BRIDGE_PROPERTY" "$requested_value" >/dev/null 2>&1
  fi
  [ "$(getprop "$UNIPERF_BRIDGE_PROPERTY" 2>/dev/null)" = "$requested_value" ]
}

current_boot_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null
}

mark_reboot_required() {
  boot_id="$(current_boot_id)"
  [ -n "$boot_id" ] || return 1
  printf '%s\n' "$boot_id" >"$STATE_DIR/reboot-required"
}

conf_get() {
  key="$1"
  file="$2"
  [ -f "$file" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$file"
}

allowed_profile() {
  case "$1" in
    powersave|balanced|performance) return 0 ;;
    *) return 1 ;;
  esac
}

atomic_replace() {
  source_file="$1"
  target_file="$2"
  target_dir="${target_file%/*}"
  mkdir -p "$target_dir"
  temp_file="$target_file.tmp.$$"
  cp -f "$source_file" "$temp_file" || return 1
  chmod 0644 "$temp_file" || return 1
  mv -f "$temp_file" "$target_file"
}

setting_set() {
  key="$1"
  value="$2"
  temp_file="$SETTINGS_FILE.tmp.$$"
  awk -F= -v wanted="$key" -v replacement="$value" '
    BEGIN { found=0 }
    $1 == wanted { print wanted "=" replacement; found=1; next }
    { print }
    END { if (!found) print wanted "=" replacement }
  ' "$SETTINGS_FILE" >"$temp_file" || return 1
  chmod 0644 "$temp_file"
  mv -f "$temp_file" "$SETTINGS_FILE"
}

decode_payload() {
  payload="$1"
  output="$2"
  printf '%s' "$payload" | base64 -d >"$output" 2>/dev/null
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_int() {
  case "$1" in
    -[0-9]*|[0-9]*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -Eq '^-?[0-9]+$'
}

daemon_pid_valid() {
  daemon_pid="$1"
  is_uint "$daemon_pid" || return 1
  [ -r "/proc/$daemon_pid/cmdline" ] || return 1
  daemon_cmdline="$(tr '\000' ' ' <"/proc/$daemon_pid/cmdline" 2>/dev/null)"
  case "$daemon_cmdline" in
    *"$MODDIR/bin/daemon.sh"*) return 0 ;;
    *) return 1 ;;
  esac
}
