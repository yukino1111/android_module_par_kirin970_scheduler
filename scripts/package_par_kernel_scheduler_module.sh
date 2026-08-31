#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
module_root="$repo_root"
output_dir="${OUTPUT_DIR:-$repo_root/dist}"
version=$(sed -n 's/^version=//p' "$module_root/module.prop")
output="$output_dir/PAR-Kirin970-Scheduler-v${version}.zip"

required=(
  module.prop customize.sh post-fs-data.sh service.sh post-mount.sh uninstall.sh action.sh
  sepolicy.rule
  bin/control.sh bin/daemon.sh bin/engine.sh lib/common.sh lib/thread-scheduler.sh
  config/settings.conf config/apps.conf config/powersave.conf
  config/balanced.conf config/performance.conf
  config/defaults/powersave.conf config/defaults/balanced.conf
  config/defaults/performance.conf
  config/legacy/balanced-v1.0.3.conf
  config/legacy/settings-v1.0.3.conf
  config/uniperf-balanced.xml config/uniperf-performance.xml
  webroot/index.html webroot/styles.css webroot/app.js
  README.md ATTRIBUTION.md LICENSE
)

for relative in "${required[@]}"; do
  [[ -f "$module_root/$relative" ]] || {
    echo "Missing module file: $relative" >&2
    exit 1
  }
done

if rg -l $'\r' "$module_root" >/dev/null; then
  echo "CRLF line endings are not allowed in the module" >&2
  exit 1
fi

for script in customize.sh post-fs-data.sh service.sh post-mount.sh uninstall.sh action.sh bin/control.sh bin/daemon.sh bin/engine.sh lib/common.sh lib/thread-scheduler.sh; do
  sh -n "$module_root/$script"
done

node --check "$module_root/webroot/app.js" >/dev/null
bash "$module_root/tests/test_module.sh"

mkdir -p "$output_dir"
rm -f "$output"
(
  cd "$module_root"
  zip -X -q -r "$output" "${required[@]}"
)
unzip -tq "$output" >/dev/null

(
  cd "$output_dir"
  sha256sum "$(basename "$output")" > "$(basename "$output").sha256"
)
echo "$output"
cat "$output.sha256"
