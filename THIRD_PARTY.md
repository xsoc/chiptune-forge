# Third-party notices

Chiptune Forge is MIT licensed. Everything bundled with it, or that it is
modelled on, is listed here with its licence. Anything added later must be
MIT-compatible: no GPL or LGPL code, in the app or in the plugin.

| Component | Where | Licence | Notes |
|---|---|---|---|
| Godot Engine 4.5 | Runtime of every build | MIT | https://godotengine.org/license |
| Inter | `assets/fonts/Inter.ttf` | SIL OFL 1.1 | `assets/fonts/Inter-OFL.txt`. Fonts stay under the OFL; they are not relicensed as MIT. |
| Space Grotesk | `assets/fonts/SpaceGrotesk.ttf` | SIL OFL 1.1 | `assets/fonts/SpaceGrotesk-OFL.txt` |
| JetBrains Mono | `assets/fonts/JetBrainsMono.ttf` | SIL OFL 1.1 | `assets/fonts/JetBrainsMono-OFL.txt` |
| sfxr (Tomas Pettersson) | Model for `addons/chipforge/runtime/chip_sfx_synth.gd` | MIT | Reimplemented in GDScript from the published algorithm; no sfxr source is bundled. |
| PCG32 (Melissa O'Neill) | `scripts/generation/pcg32.gd` | Apache 2.0 or MIT | Reimplemented from the paper and reference output; no PCG source is bundled. |
| hUGEDriver (Nick Faro and contributors) | `assets/gameboy/hUGEDriver/`, bundled in Game Boy exports; modelled in `scripts/targets/gameboy/huge_player.gd` | Public domain | https://github.com/SuperDisk/hUGEDriver. Includes its `tools/rgb2sdas.py`. |
| hardware.inc (gbdev) | `assets/gameboy/hUGEDriver/include/hardware.inc` | CC0 | https://github.com/gbdev/hardware.inc |
| FamiStudio (Mathieu Gauthier) | Model for `scripts/targets/nes/nes_player.gd` and `famistudio_writer.gd` | MIT | https://github.com/BleuBleu/FamiStudio. The text project format, NTSC note table, volume table and noise mapping were reimplemented from its documented behaviour; no FamiStudio code is bundled. |
| 2A03 mixer formulas (nesdev wiki) | `scripts/targets/nes/nes_apu.gd` | Public technique | No code copied. |
| PolyBLEP oscillator method | `addons/chipforge/runtime/chip_voice.gd` | Public technique | No code copied. |

Game Boy ROMs are built with GBDK-2020 and RGBDS, which users install
themselves and CI downloads; neither is bundled. Exported Game Boy projects
link hUGEDriver, which is public domain, so a game built from them carries no
licence obligations from it.

NES exports are FamiStudio projects. FamiStudio, which users install
themselves and CI downloads, is MIT licensed, and so is its sound engine, so
a game built from an export carries only the MIT notice of that engine.

The icons in `assets/ui/` and `addons/chipforge/icons/` were drawn for this
project and are MIT licensed with the rest of the code.

## Music and sounds you make

Songs and sound effects generated with Chiptune Forge belong to whoever made
them. They can be used for any purpose, including commercial games, with no
royalties or credit required. Each exported file carries a note saying so.
