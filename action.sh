#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"

current="$(conf_get global_profile "$SETTINGS_FILE")"
case "$current" in
  powersave) next=balanced ;;
  balanced) next=performance ;;
  performance|*) next=powersave ;;
esac

setting_set global_profile "$next"
touch "$STATE_DIR/reload"

printf 'PAR Kirin 970 Scheduler\n'
printf 'Global profile: %s -> %s\n' "$current" "$next"
printf 'Dynamic app rules: %s\n' "$(conf_get dynamic_enabled "$SETTINGS_FILE")"
printf 'The running daemon will apply the change within a few seconds.\n'
