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
| FamiStudio (Mathieu Gauthier) | Model for `scripts/targets/nes/nes_player.gd`, `famistudio_writer.gd` and `famistudio_asm_writer.gd` | MIT | https://github.com/BleuBleu/FamiStudio. The text project format, NTSC note table, volume table and noise mapping were reimplemented from its documented behaviour. `famistudio_asm_writer.gd` is a GDScript port of the parts of its sound engine exporter (FamitoneMusicFile.cs, FamitoneSoundEffectFile.cs, TempoUtils.cs) the app needs. |
| FamiStudio sound engine 4.5.4 | `assets/nes/famistudio/`, bundled in NES exports | MIT (engine file: all-permissive notice) | `famistudio_ca65.s` and `famistudio_cc65.h`, unchanged. |
| 2A03 mixer formulas (nesdev wiki) | `scripts/targets/nes/nes_apu.gd` | Public technique | No code copied. |
| PSGlib (sverx) | Data format written by `scripts/targets/sms/psg_writer.gd`; modelled in `sms_player.gd` | BSD 3-clause | https://github.com/sverx/PSGlib. The format was reimplemented from its converter's documented behaviour; no PSGlib code is bundled. CI builds its tools to check the exports. |
| SN76489 behaviour (SMS Power! documentation) | `scripts/targets/sms/sms_psg.gd` | Public technique | No code copied. |
| YM2612 behaviour (Yamaha OPN2 documentation, MAME and Nuked-OPN2 write-ups) | `scripts/targets/genesis/ym2612.gd` | Public technique | Reimplemented from the documented behaviour (phase increments, detune table, envelope rates, algorithms); no emulator code is bundled. |
| SGDK (Stephane Dallongeville) | Target of the Mega Drive exports (`scripts/targets/genesis/md_vgm_writer.gd`, `md_sfx.gd`) | MIT | https://github.com/Stephane-D/SGDK. Not bundled: users install it, and CI runs its Docker image to build the example ROM. |
| libvgm (Valley Bell) and stable-retro (Genesis Plus GX) | CI only, to play the Mega Drive exports | Various | Downloaded by CI to check the exports; never bundled or linked. |
| PVSnesLib and SNESMod (Alekmaul, mukunda and contributors) | Target of the SNES exports; modelled in `scripts/targets/snes/snes_player.gd`; `snes_brr.gd` ports smconv's BRR encoder | MIT | https://github.com/alekmaul/pvsneslib. `snes_brr.gd` is a GDScript port of smconv's `brr.cpp`, and `snes_song.gd` carries SNESMod's frequency table (`LUT_FTAB` in `sm_spc_wla.asm`). Not bundled otherwise: users install PVSnesLib, and CI builds the example ROM with it. |
| S-DSP behaviour (fullsnes and SNES development wiki write-ups) | `scripts/targets/snes/snes_dsp.gd` | Public technique | Reimplemented from the documented behaviour (BRR decoding, pitch, GAIN modes, echo); no emulator code is bundled. |
| libopenmpt and stable-retro (Snes9x) | CI only, to play the SNES exports | Various | Installed by CI to check the exports; never bundled or linked. |
| HuCC (pce-devel/huc) and stable-retro (Mednafen PCE Fast) | CI only, to build and play the PC Engine example ROMs | Various | Cloned and built by CI; never bundled or linked. The PC Engine player (`assets/pce/pce_player.c`) is our own MIT code. |
| Pasmo and libvgm (ValleyBell/libvgm) | CI only, to assemble the MSX and Spectrum examples and play the AY VGM | GPL-3.0 (Pasmo), libvgm's licence | Installed or built by CI; never bundled or linked. The Z80 player (`assets/msx/ay_player.asm`) and the Z80 emulator in `tools/ay_check.py` are our own MIT code. |
| AY-3-8910 behaviour (General Instrument datasheet, measured volume table) | `scripts/targets/msx/ay_psg.gd` | Public technique | Reimplemented from the documented behaviour (tone and noise periods, mixer, 16 volume steps); no emulator code is bundled. |
| HuC6280 PSG behaviour (Paul Clifford's PSG notes, Mednafen's documented volume steps) | `scripts/targets/pce/pce_psg.gd` | Public technique | Reimplemented from the documented behaviour (waveforms, noise, 1.5 dB volume and balance steps); no emulator code is bundled. |
| PolyBLEP oscillator method | `addons/chipforge/runtime/chip_voice.gd` | Public technique | No code copied. |

Game Boy ROMs are built with GBDK-2020 and RGBDS, which users install
themselves and CI downloads; neither is bundled. Exported Game Boy projects
link hUGEDriver, which is public domain, so a game built from them carries no
licence obligations from it.

NES exports are data for FamiStudio's sound engine, bundled with the engine,
plus the FamiStudio project. FamiStudio is MIT licensed and its sound engine
file carries an all-permissive notice, so a game built from an export needs
at most to keep that notice in the engine's source. CI downloads FamiStudio
and cc65 to check the exports; neither program is bundled.

Master System exports are PSGlib data. PSGlib, which users get with
devkitSMS or from its own repository, plays it; the data itself carries no
licence terms from PSGlib.

Mega Drive exports are VGM files and 8-bit WAVs. SGDK, which users install
themselves, converts them and plays them with its XGM driver; SGDK is MIT
licensed, so a game built with it carries only SGDK's MIT notice.

SNES exports are Impulse Tracker modules (and BRR samples for sound effects)
with a small PVSnesLib project. PVSnesLib, which users install themselves,
converts them with smconv and plays them with SNESMod; PVSnesLib is MIT
licensed, so a game built with it carries only its MIT notice.

PC Engine exports are data for our own player, `pce_player.c`, which ships
with them under the MIT licence; HuCC, which users install themselves,
compiles it into their game.

MSX and ZX Spectrum 128 exports are data for our own Z80 player,
`ay_player.asm`, which ships with them under the MIT licence, plus a VGM
file.

The icons in `assets/ui/` and `addons/chipforge/icons/` were drawn for this
project and are MIT licensed with the rest of the code.

## Music and sounds you make

Songs and sound effects generated with Chiptune Forge belong to whoever made
them. They can be used for any purpose, including commercial games, with no
royalties or credit required. Each exported file carries a note saying so.
