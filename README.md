# PAR Kirin 970 Scheduler

## What this repository implements

The reproducible source and packaging home for a device-specific KernelSU /
SukiSU scheduler module for Huawei nova 3 (`PAR-AL00`, Kirin 970) on the PAR
Android 13 ROM.

The module provides:

- a systemless override of the single effective vendor UniPerf XML;
- powersave, balanced, and performance profiles, with balanced selected by
  default;
- global, per-application, and custom profile controls in KernelSU WebUI;
- an English/Chinese WebUI that follows the system language on first use and
  remembers manual language changes;
- foreground-application switching with cached settings and low idle polling
  overhead;
- guarded writes to existing writable CPUFreq, GPU devfreq, and EAS nodes;
- a boot-scoped switch for the PAR ROM's UniPerf framework event bridge; and
- restore-to-default actions for individual profiles or all three profiles.

It does not modify thermal policy, charging policy, vendor init, `/data/system`,
or any physical partition. It contains no Huawei or Google proprietary binary,
no extracted stock vendor XML, and no code from another scheduler module.

The included balanced and performance UniPerf policies are maintained PAR
defaults rather than backups of the stock policy. Removing the module and
rebooting lets Mountify rebuild its overlay without this module, restoring the
untouched vendor policy.

## Disclaimer

This is a personal project shared as-is. A scheduler configuration can increase
power use, heat, or instability, and a broken root module can prevent Android
from starting normally. You accept all risk and responsibility for installation
and recovery. No warranty, device porting, or recovery support is provided.

## Compatibility

- Device: Huawei nova 3 (`PAR-AL00`, Kirin 970).
- ROM: the companion
  [PAR Android 13 ROM](https://github.com/yukino1111/android_gsi_alphadroid_par)
  with its device-gated UniPerf bridge.
- Root manager: modern KernelSU or SukiSU with module WebUI support.
- Mounting metamodule: Mountify is required; version 2.0.3 in automatic tmpfs
  mode is the verified configuration.

This is a regular module and deliberately does not declare `metamodule=true`.
KernelSU permits only one active mounting metamodule, which remains Mountify.
Other devices, SoCs, ROMs, or vendor layouts are unsupported.

## Build

Run the packaging script from any working directory:

```bash
./scripts/package_par_kernel_scheduler_module.sh
```

The validated ZIP and a matching `.sha256` file are written under `dist/`.
Generated packages are ignored by Git and should be attached to a release
rather than committed.

## Installation

Install and enable Mountify first. Flash the generated ZIP in KernelSU/SukiSU,
then perform a complete reboot so the vendor UniPerf service reloads its policy.
A soft restart of `system_server` is not sufficient after changing UniPerf XML.

Use the module's WebUI to select a global profile, define application rules, or
edit and restore custom profile parameters. The module action button cycles the
global profile without requiring Scene.

To uninstall, remove the module in the root manager and reboot. No vendor file
needs to be restored manually because the override is systemless.

## License

Original source, configuration, scripts, and documentation in this repository
use Apache-2.0. See [`LICENSE`](LICENSE) and
[`ATTRIBUTION.md`](ATTRIBUTION.md).

## Acknowledgements

- [Cirrest](https://github.com/Cirrest): this project draws on the scheduling
  approach and observable runtime behavior of Cirrest's Kirin 970 scheduling
  module. The implementation here was rewritten for PAR, with a different safe
  mounting model, three-profile WebUI, guarded sysfs access, and ROM-controlled
  UniPerf delivery. No original executable, service/control script, or private
  binary is included.
