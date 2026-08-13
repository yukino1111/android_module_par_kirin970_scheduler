#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"

set_uniperf_bridge_enabled 0

daemon_pid="$(cat "$STATE_DIR/daemon.pid" 2>/dev/null)"
if daemon_pid_valid "$daemon_pid"; then
  kill "$daemon_pid" 2>/dev/null
  sleep 1
  daemon_pid_valid "$daemon_pid" && kill -9 "$daemon_pid" 2>/dev/null
fi
rm -f "$STATE_DIR/daemon.pid" "$STATE_DIR/reload"

# Mountify merges module contents into shared OverlayFS mounts. Framework event
# delivery is disabled immediately; KernelSU removes
# this module and Mountify rebuilds those mounts without it on the next reboot.
