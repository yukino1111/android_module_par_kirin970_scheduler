#!/system/bin/sh
MODDIR=${0%/*}

# Recheck after Android finishes bringing up vendor mounts. Some managers run
# module service scripts while Mountify is still finalizing its shared overlay.
attempt=0
while [ "$attempt" -lt 10 ]; do
  "$MODDIR/post-mount.sh"
  [ "$(sed -n 's/^mounted=//p' "$MODDIR/state/mount-status.conf" 2>/dev/null)" = 1 ] && break
  attempt=$((attempt + 1))
  sleep 1
done
exec "$MODDIR/bin/daemon.sh" >>"$MODDIR/state/daemon.log" 2>&1
