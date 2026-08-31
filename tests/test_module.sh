#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d /tmp/par-scheduler-test.XXXXXX)
cleanup() {
  case "$test_root" in /tmp/par-scheduler-test.*) rm -rf -- "$test_root" ;; esac
}
trap cleanup EXIT

module_root="$test_root/module"
mkdir -p "$module_root"
cp -a "$repo_root/bin" "$repo_root/config" "$repo_root/lib" "$module_root/"
mkdir -p "$module_root/state"

for script in "$repo_root"/*.sh "$repo_root"/bin/*.sh "$repo_root"/lib/*.sh; do
  sh -n "$script"
done
node --check "$repo_root/webroot/app.js" >/dev/null

for profile in powersave balanced performance; do
  [[ $(awk 'NF { count++ } END { print count+0 }' "$repo_root/config/$profile.conf") == 20 ]]
  payload=$(base64 -w 0 <"$repo_root/config/$profile.conf")
  sh "$module_root/bin/control.sh" save-profile "$profile" "$payload"
done

cp "$repo_root/config/performance.conf" "$test_root/invalid.conf"
sed -i 's/^ddr_latency_min=.*/ddr_latency_min=broken/' "$test_root/invalid.conf"
invalid_payload=$(base64 -w 0 <"$test_root/invalid.conf")
if sh "$module_root/bin/control.sh" save-profile performance "$invalid_payload"; then
  echo "invalid DDR latency vote was accepted" >&2
  exit 1
fi

install_root="$test_root/install"
old_module="$test_root/old-module"
mock_bin="$test_root/mock-bin"
mkdir -p "$install_root" "$old_module/config" "$mock_bin"
cp -a "$repo_root/config" "$repo_root/bin" "$repo_root/lib" "$install_root/"
cp -a "$repo_root/customize.sh" "$repo_root/action.sh" "$repo_root/service.sh" \
  "$repo_root/post-mount.sh" "$repo_root/uninstall.sh" "$install_root/"
for profile in powersave balanced performance; do
  head -n 17 "$repo_root/config/$profile.conf" >"$old_module/config/$profile.conf"
done
cp "$repo_root/config/legacy/balanced-v1.0.3.conf" "$old_module/config/balanced.conf"
sed -i 's/^eas_boost=.*/eas_boost=20/' "$old_module/config/performance.conf"
cp "$repo_root/config/legacy/settings-v1.0.3.conf" "$old_module/config/settings.conf"
cp "$repo_root/config/apps.conf" "$old_module/config/apps.conf"
printf '%s\n' '#!/bin/sh' 'case "$1" in ro.product.device) echo HWPAR ;; ro.product.model) echo PAR-AL00 ;; ro.board.platform) echo kirin970 ;; esac' >"$mock_bin/getprop"
chmod 0755 "$mock_bin/getprop"
abort() { echo "$*" >&2; exit 1; }
ui_print() { :; }
set_perm() { chmod "$4" "$1"; }
export -f abort ui_print set_perm
PATH="$mock_bin:$PATH" KSU=true ARCH=arm64 API=33 KSU_HAS_METAMODULE=true KSU_METAMODULE=mountify \
  MODPATH="$install_root" PAR_ACTIVE_MODULE="$old_module" bash "$install_root/customize.sh"
[[ $(awk 'NF { count++ } END { print count+0 }' "$install_root/config/performance.conf") == 20 ]]
grep -qx 'eas_boost=1' "$install_root/config/performance.conf"
grep -qx 'stune_boost=10' "$install_root/config/performance.conf"
grep -qx 'ddr_latency_min=1244000000' "$install_root/config/performance.conf"
! grep -q '^thread_placement=' "$install_root/config/settings.conf"
grep -qx 'poll_interval=1' "$install_root/config/settings.conf"
grep -qx 'big_hispeed=1498000' "$install_root/config/balanced.conf"
grep -qx 'eas_boost=1' "$install_root/config/balanced.conf"
grep -qx 'stune_boost=8' "$install_root/config/balanced.conf"

reinstall_root="$test_root/reinstall"
old_v11_module="$test_root/old-v11-module"
mkdir -p "$reinstall_root" "$old_v11_module/config"
cp -a "$repo_root/config" "$repo_root/bin" "$repo_root/lib" "$reinstall_root/"
cp -a "$repo_root/customize.sh" "$repo_root/action.sh" "$repo_root/service.sh" \
  "$repo_root/post-mount.sh" "$repo_root/uninstall.sh" "$reinstall_root/"
cp "$install_root/config/settings.conf" "$old_v11_module/config/settings.conf"
printf '%s\n' 'thread_placement=0' >>"$old_v11_module/config/settings.conf"
PATH="$mock_bin:$PATH" KSU=true ARCH=arm64 API=33 KSU_HAS_METAMODULE=true KSU_METAMODULE=mountify \
  MODPATH="$reinstall_root" PAR_ACTIVE_MODULE="$old_v11_module" bash "$reinstall_root/customize.sh"
! grep -q '^thread_placement=' "$reinstall_root/config/settings.conf"

sysroot="$test_root/sysroot"
make_node() {
  node_path="$1"
  node_value="$2"
  mkdir -p "${node_path%/*}"
  printf '%s\n' "$node_value" >"$node_path"
}

for cluster in cpu0 cpu4; do
  cluster_dir="$sysroot/sys/devices/system/cpu/$cluster/cpufreq"
  make_node "$cluster_dir/cpuinfo_min_freq" "$([[ $cluster == cpu0 ]] && printf 509000 || printf 682000)"
  make_node "$cluster_dir/scaling_min_freq" 0
  make_node "$cluster_dir/scaling_max_freq" 3000000
  for key in hispeed_freq go_hispeed_load target_loads above_hispeed_delay min_sample_time; do
    make_node "$cluster_dir/interactive/$key" 0
  done
done
gpu_dir="$sysroot/sys/devices/platform/e82c0000.mali/devfreq/gpufreq"
make_node "$gpu_dir/available_frequencies" "103750000 332000000 415000000 767000000"
make_node "$gpu_dir/min_freq" 0
make_node "$gpu_dir/max_freq" 999999999
make_node "$sysroot/sys/kernel/eas/boost" 0
make_node "$sysroot/sys/class/devfreq/ddrfreq_latency/min_freq" 0

PAR_SYS_ROOT="$sysroot" sh "$module_root/bin/engine.sh" apply performance
[[ $(<"$sysroot/sys/kernel/eas/boost") == 1 ]]
[[ $(<"$sysroot/sys/class/devfreq/ddrfreq_latency/min_freq") == 1244000000 ]]

PAR_SYS_ROOT="$sysroot" sh "$module_root/bin/engine.sh" restore-stock-scheduler
[[ $(<"$sysroot/sys/kernel/eas/boost") == 0 ]]
[[ $(<"$sysroot/sys/class/devfreq/ddrfreq_latency/min_freq") == 0 ]]

proc_root="$test_root/proc"
data_root="$test_root/data-adb"
mkdir -p "$proc_root/123/task/123" "$proc_root/123/task/124" "$proc_root/124" "$data_root/modules"
make_node "$sysroot/dev/cpuset/top-app/cgroup.procs" 123
printf '%s' com.example.game >"$proc_root/123/cmdline"
printf 'Tgid:\t123\n' >"$proc_root/123/status"
printf 'Tgid:\t123\n' >"$proc_root/124/status"
printf '%s\n' com.example.game >"$proc_root/123/task/123/comm"
printf '%s\n' RenderThread >"$proc_root/123/task/124/comm"
taskset_log="$test_root/taskset.log"
taskset_mock="$test_root/taskset"
printf '%s\n' '#!/bin/sh' 'printf "%s %s %s\n" "$1" "$2" "$3" >>"$PAR_TASKSET_LOG"' >"$taskset_mock"
chmod 0755 "$taskset_mock"

stune_root="$test_root/stune"
make_node "$stune_root/tasks" 0
make_node "$stune_root/par-game/tasks" 0
make_node "$stune_root/par-game/schedtune.boost" 0
make_node "$stune_root/par-game/schedtune.prefer_idle" 0

export PAR_SYS_ROOT="$sysroot" PAR_PROC_ROOT="$proc_root" PAR_DATA_ADB_ROOT="$data_root"
export PAR_TASKSET_BIN="$taskset_mock" PAR_TASKSET_LOG="$taskset_log" PAR_STUNE_ROOT="$stune_root"
MODDIR="$module_root"
. "$module_root/lib/common.sh"
. "$module_root/lib/thread-scheduler.sh"
last_thread_key=
refresh_top_app_rows
grep -qx '123|com.example.game' "$TOP_APP_ROWS"
thread_reconcile com.example.game performance
[[ $(grep -c '^-p f0 ' "$taskset_log") == 2 ]]
[[ $(<"$stune_root/par-game/schedtune.boost") == 10 ]]
[[ $(<"$stune_root/par-game/schedtune.prefer_idle") == 1 ]]
thread_reconcile com.example.game balanced
[[ $(grep -c '^-p ff ' "$taskset_log") == 2 ]]
[[ $(grep -c '^-p f0 ' "$taskset_log") == 2 ]]
[[ $(<"$stune_root/par-game/schedtune.boost") == 8 ]]
grep -qx 'active:com.example.game' "$THREAD_STATUS"

mkdir -p "$data_root/modules/asoul_affinity_opt"
thread_reconcile com.example.game performance
grep -qx blocked-asoul "$THREAD_STATUS"

echo "all scheduler module tests passed"
