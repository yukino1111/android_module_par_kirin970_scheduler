# Source attribution

The shell control plane, WebUI, configuration schema, profile defaults, and
packaging script in this repository are maintained by the PAR project.

## Cirrest scheduler concept

The overall idea of applying Kirin 970 scheduling profiles and some optional
performance parameter choices were informed by the scheduling approach and
observable runtime behavior of a module made by GitHub user
[Cirrest](https://github.com/Cirrest). The PAR implementation is independently
written. It does not include Cirrest's executable, service/control scripts, or
other binary payloads.

## Huawei compatibility surface

The UniPerf event identifiers and XML structure are functional compatibility
data needed to communicate with the Huawei vendor service already present on
the device. The two policy XML files in this repository are PAR-authored
policies validated on the target device; they are not copies or backups of the
stock vendor policy. No Huawei proprietary implementation or extracted binary
is distributed here.
