# hUGEDriver (vendored)

The Game Boy music driver used by Chiptune Forge's Game Boy exports, from
https://github.com/SuperDisk/hUGEDriver at commit
d6863d29472e1e2fa75e75c3c826cda7e70b0c8e. hUGEDriver and hUGETracker are
dedicated to the public domain. `include/hardware.inc` is from
https://github.com/gbdev/hardware.inc (CC0).

The files are copied unchanged. CI builds `lib/hUGEDriver.lib` for GBDK-2020
from them (see `tools/build_hugedriver.sh`) and bundles it into the app, so
exported projects need only GBDK-2020 to build. The library is not checked in.
