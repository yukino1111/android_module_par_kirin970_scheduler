#!/system/bin/sh

TOP_APP_CGROUP_ROOT="${PAR_SYS_ROOT:-}/dev/cpuset/top-app"
ASOUL_CPUSET_ROOT="${PAR_SYS_ROOT:-}/dev/cpuset/asopt"
THREAD_PROC_ROOT="${PAR_PROC_ROOT:-/proc}"
THREAD_DATA_ADB_ROOT="${PAR_DATA_ADB_ROOT:-/data/adb}"
STUNE_ROOT="${PAR_STUNE_ROOT:-${PAR_SYS_ROOT:-}/dev/stune}"
STUNE_GROUP="$STUNE_ROOT/par-game"
STUNE_MOUNT_MARKER="$STATE_DIR/stune-mounted-by-par"
TOP_APP_ROWS="$STATE_DIR/top-app.rows"
MANAGED_THREADS="$STATE_DIR/managed-threads"
THREAD_STATUS="$STATE_DIR/thread-status"

thread_taskset_bin() {
  if [ -n "${PAR_TASKSET_BIN:-}" ] && [ -x "$PAR_TASKSET_BIN" ]; then
    printf '%s\n' "$PAR_TASKSET_BIN"
  elif [ -x /system/bin/taskset ]; then
    printf '%s\n' /system/bin/taskset
  elif command -v taskset >/dev/null 2>&1; then
    command -v taskset
  else
    return 1
  fi
}

thread_set_affinity() {
  thread_mask="$1"
  thread_tid="$2"
  thread_taskset="$(thread_taskset_bin)" || return 1
  "$thread_taskset" -p "$thread_mask" "$thread_tid" >/dev/null 2>&1
}

thread_node_write() {
  thread_node="$1"
  thread_value="$2"
  [ -e "$thread_node" ] && [ -w "$thread_node" ] || return 1
  echo -n "$thread_value" >"$thread_node" 2>/dev/null
}

thread_prepare_stune() {
  stune_profile="$1"
  stune_profile_file="$CONFIG_DIR/$stune_profile.conf"
  [ -f "$stune_profile_file" ] || return 1

  if [ ! -e "$STUNE_ROOT/tasks" ]; then
    stune_created_root=0
    if [ ! -d "$STUNE_ROOT" ]; then
      mkdir -p "$STUNE_ROOT" || return 1
      stune_created_root=1
    fi
    mount -t cgroup -o schedtune none "$STUNE_ROOT" >/dev/null 2>&1 || {
      [ "$stune_created_root" = 1 ] && rmdir "$STUNE_ROOT" 2>/dev/null || true
      return 1
    }
    : >"$STUNE_MOUNT_MARKER"
  fi

  mkdir -p "$STUNE_GROUP" || return 1
  [ -e "$STUNE_GROUP/tasks" ] || return 1
  thread_node_write "$STUNE_GROUP/schedtune.boost" "$(conf_get stune_boost "$stune_profile_file")" || return 1
  thread_node_write "$STUNE_GROUP/schedtune.prefer_idle" "$(conf_get stune_prefer_idle "$stune_profile_file")" || return 1
}

thread_leave_stune() {
  leave_tid="$1"
  [ -w "$STUNE_ROOT/tasks" ] || return 0
  thread_node_write "$STUNE_ROOT/tasks" "$leave_tid" || true
}

process_package() {
  process_pid="$1"
  [ -r "$THREAD_PROC_ROOT/$process_pid/cmdline" ] || return 1
  process_cmdline="$(tr '\000' '\n' <"$THREAD_PROC_ROOT/$process_pid/cmdline" 2>/dev/null | sed -n '1p')"
  process_package_name="${process_cmdline%%:*}"
  case "$process_package_name" in
    ''|*[!A-Za-z0-9._]*) return 1 ;;
  esac
  printf '%s\n' "$process_package_name"
}

top_app_pids() {
  if [ -r "$TOP_APP_CGROUP_ROOT/cgroup.procs" ]; then
    cat "$TOP_APP_CGROUP_ROOT/cgroup.procs" 2>/dev/null
  elif [ -r "$TOP_APP_CGROUP_ROOT/tasks" ]; then
    # Some cgroup-v1 layouts expose only tasks. Convert TIDs back to TGIDs.
    while IFS= read -r top_tid; do
      case "$top_tid" in ''|*[!0-9]*) continue ;; esac
      awk '/^Tgid:/ { print $2; exit }' "$THREAD_PROC_ROOT/$top_tid/status" 2>/dev/null
    done <"$TOP_APP_CGROUP_ROOT/tasks"
  fi

  # A-SOUL may move the selected game out of top-app into its own cpuset.
  # Include that group only for foreground detection; PAR affinity/stune stays
  # disabled whenever the external module is active.
  if asoul_active; then
    if [ -r "$ASOUL_CPUSET_ROOT/cgroup.procs" ]; then
      cat "$ASOUL_CPUSET_ROOT/cgroup.procs" 2>/dev/null
    elif [ -r "$ASOUL_CPUSET_ROOT/tasks" ]; then
      while IFS= read -r asoul_tid; do
        case "$asoul_tid" in ''|*[!0-9]*) continue ;; esac
        awk '/^Tgid:/ { print $2; exit }' "$THREAD_PROC_ROOT/$asoul_tid/status" 2>/dev/null
      done <"$ASOUL_CPUSET_ROOT/tasks"
    fi
  fi
}

refresh_top_app_rows() {
  top_rows_temp="$TOP_APP_ROWS.tmp.$$"
  : >"$top_rows_temp"
  top_app_pids | sort -nu | while IFS= read -r top_pid; do
    case "$top_pid" in ''|*[!0-9]*) continue ;; esac
    top_package="$(process_package "$top_pid")" || continue
    printf '%s|%s\n' "$top_pid" "$top_package"
  done >"$top_rows_temp"
  mv -f "$top_rows_temp" "$TOP_APP_ROWS"
}

asoul_active() {
  asoul_dir="$THREAD_DATA_ADB_ROOT/modules/asoul_affinity_opt"
  [ -d "$asoul_dir" ] && [ ! -e "$asoul_dir/disable" ] && [ ! -e "$asoul_dir/remove" ]
}

thread_is_critical() {
  thread_name="$1"
  case "$thread_name" in
    UnityMain|UnityGfx|RenderThread|RenderThread-*|GameThread|GameThread-*|GLThread|GLThread-*|RHIThread|RHIThread-*|MainThread|UE4GameThread|VulkanThread|VulkanThread-*) return 0 ;;
    *) return 1 ;;
  esac
}

thread_is_ui_critical() {
  thread_name="$1"
  case "$thread_name" in
    RenderThread|RenderThread-*|GLThread|GLThread-*|hwuiTask*|HwuiTask*) return 0 ;;
    *) return 1 ;;
  esac
}

thread_already_managed() {
  managed_tid="$1"
  [ -s "$MANAGED_THREADS" ] && grep -q "^$managed_tid|" "$MANAGED_THREADS" 2>/dev/null
}

thread_restore_managed() {
  [ -s "$MANAGED_THREADS" ] || { : >"$MANAGED_THREADS"; return 0; }
  while IFS='|' read -r managed_tid managed_package managed_affinity managed_extra; do
    [ -z "$managed_extra" ] || continue
    case "$managed_tid" in ''|*[!0-9]*) continue ;; esac
    managed_tgid="$(awk '/^Tgid:/ { print $2; exit }' "$THREAD_PROC_ROOT/$managed_tid/status" 2>/dev/null)"
    [ -n "$managed_tgid" ] || continue
    current_package="$(process_package "$managed_tgid")" || continue
    [ "$current_package" = "$managed_package" ] || continue
    thread_leave_stune "$managed_tid"
    case "$managed_affinity" in ''|1) thread_set_affinity ff "$managed_tid" || true ;; esac
  done <"$MANAGED_THREADS"
  : >"$MANAGED_THREADS"
}

thread_bind_foreground() {
  bind_package="$1"
  bind_profile="$2"
  [ -r "$TOP_APP_ROWS" ] || return 0
  while IFS='|' read -r bind_pid row_package row_extra; do
    [ -z "$row_extra" ] || continue
    [ "$row_package" = "$bind_package" ] || continue
    for bind_task_dir in "$THREAD_PROC_ROOT/$bind_pid"/task/[0-9]*; do
      [ -d "$bind_task_dir" ] || continue
      bind_tid="${bind_task_dir##*/}"
      bind_name="$(cat "$bind_task_dir/comm" 2>/dev/null)"
      bind_affinity=0
      bind_stune_candidate=0
      if [ "$bind_profile" = performance ]; then
        bind_stune_candidate=1
      elif [ "$bind_tid" = "$bind_pid" ] || thread_is_ui_critical "$bind_name"; then
        bind_stune_candidate=1
      fi
      if [ "$bind_profile" = performance ] &&
         { [ "$bind_tid" = "$bind_pid" ] || thread_is_critical "$bind_name"; }; then
        bind_affinity=1
      fi
      thread_already_managed "$bind_tid" && continue
      bind_stune=0
      if [ "$bind_stune_candidate" = 1 ] && [ "$thread_stune_ready" = 1 ] &&
         thread_node_write "$STUNE_GROUP/tasks" "$bind_tid"; then
        bind_stune=1
      fi
      bind_affinity_applied=0
      if [ "$bind_affinity" = 1 ] && thread_set_affinity f0 "$bind_tid"; then
        bind_affinity_applied=1
      fi
      if [ "$bind_stune" = 1 ] || [ "$bind_affinity_applied" = 1 ]; then
        printf '%s|%s|%s\n' "$bind_tid" "$bind_package" "$bind_affinity_applied" >>"$MANAGED_THREADS"
      fi
    done
  done <"$TOP_APP_ROWS"
}

thread_reconcile() {
  requested_package="$1"
  requested_profile="$2"
  requested_key="$requested_package|$requested_profile"

  if [ "$requested_key" != "$last_thread_key" ]; then
    thread_restore_managed
    last_thread_key="$requested_key"
  fi

  if asoul_active; then
    thread_restore_managed
    printf '%s\n' blocked-asoul >"$THREAD_STATUS"
    return 0
  fi
  case "$requested_profile" in balanced|performance) ;;
    *) printf '%s\n' idle >"$THREAD_STATUS"; return 0 ;;
  esac
  if [ -z "$requested_package" ]; then
    printf '%s\n' idle >"$THREAD_STATUS"
    return 0
  fi

  thread_stune_ready=0
  thread_prepare_stune "$requested_profile" && thread_stune_ready=1
  thread_bind_foreground "$requested_package" "$requested_profile"
  if [ "$thread_stune_ready" = 1 ]; then
    printf 'active:%s\n' "$requested_package" >"$THREAD_STATUS"
  elif [ "$requested_profile" = balanced ]; then
    printf '%s\n' unsupported-stune >"$THREAD_STATUS"
  elif ! thread_taskset_bin >/dev/null; then
    printf '%s\n' unsupported-taskset >"$THREAD_STATUS"
  else
    printf 'affinity-only:%s\n' "$requested_package" >"$THREAD_STATUS"
  fi
}

thread_remove_stune() {
  thread_restore_managed
  rmdir "$STUNE_GROUP" 2>/dev/null || true
  if [ -e "$STUNE_MOUNT_MARKER" ]; then
    umount "$STUNE_ROOT" >/dev/null 2>&1 || true
    rmdir "$STUNE_ROOT" 2>/dev/null || true
    rm -f "$STUNE_MOUNT_MARKER"
  fi
}
