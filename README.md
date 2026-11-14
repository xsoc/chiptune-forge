# Chiptune Forge

Chiptune Forge makes royalty-free chiptune music and retro sound effects for
games. Pick a vibe and a style, press Generate, and keep what you like. It
runs on phones, desktops and the web, and it exports straight into Godot.

- **Music mode.** 147 vibes in 11 categories and 100 styles in 9 families.
  Blend up to three vibes, set intensity, complexity, tempo, key, form and
  length, then lock the layers you like and regenerate the rest.
- **Sound FX mode.** About 160 presets in 12 categories, from menu clicks to
  boss roars. Every tap gives a new take; mutate it, tweak it and collect the
  keepers into a sound kit.
- **Adaptive music.** Every song has layers and four states (Explore,
  Tension, Combat, Boss) that the Godot plugin can fade between by intensity.
- **Exports.** `.chipsong`, `.chipsfx` and `.chipkit` JSON for the Godot
  plugin, WAV with loop points (or one WAV per layer), and MIDI.
- **Game Boy target.** Pick the Game Boy on the Export screen and the song is
  arranged for its four channels, previews play through an emulated Game Boy
  sound chip, and the export is a GBDK-2020 project (C data for hUGEDriver,
  an example `main.c` and a Makefile) that builds into a ROM. Sound effects
  convert too, with a small player that shares a channel with the music.
- **NES target.** Pick the NES and the song is arranged for the 2A03's two
  pulses, triangle and noise, previews play through an emulated NES sound
  chip, and the export is a [FamiStudio](https://famistudio.org) project that
  FamiStudio turns into data for its sound engine, an NSF or a ROM. Sound
  effects export as a FamiStudio sound effect project.
- **Master System / Game Gear target.** Pick the Master System and the song
  is arranged for the SN76489's three squares and noise, previews play
  through an emulated SN76489, and the export is
  [PSGlib](https://github.com/sverx/PSGlib) data (a `.psg` file and a C
  array for devkitSMS) plus a VGM. Sound effects export as PSGlib sound
  effects that play over the music.
- **Mega Drive / Genesis target.** Pick the Mega Drive and the song is
  arranged for the YM2612's FM channels and the SN76489: FM lead, harmony,
  arpeggio, bass and drums, with the pad's chords on the squares. Previews
  play through an emulated YM2612 and SN76489, and the export is a VGM that
  [SGDK](https://github.com/Stephane-D/SGDK) turns into XGM music, with a
  minimal SGDK program. Sound effects export as 8-bit samples for XGM.
- **Seeds.** The same settings and seed always give the same song, on every
  platform.

Everything you make is yours, for any use, with no royalties or credit
required.

## Screenshots

![Generate screen on desktop: vibe and style pickers, feel and length controls, and the song preview](docs/screenshots/desktop-generate.png)

<table>
  <tr>
    <td><img src="docs/screenshots/desktop-layers.png" alt="Layers screen: lock or regenerate each layer and set the adaptive states"></td>
    <td><img src="docs/screenshots/desktop-sfx.png" alt="Sound FX mode: presets, waveform preview and tweak sliders"></td>
  </tr>
  <tr>
    <td align="center">Layers and adaptive states</td>
    <td align="center">Sound FX mode</td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/screenshots/desktop-export.png" alt="Export screen: target, limits check and formats"></td>
  </tr>
  <tr>
    <td colspan="2" align="center">Export</td>
  </tr>
</table>

On a phone the same screens stack into one column with navigation at the
bottom:

<p align="center">
  <img src="docs/screenshots/phone-generate.png" width="250" alt="Generate screen on a phone">
  <img src="docs/screenshots/phone-layers.png" width="250" alt="Layers screen on a phone">
  <img src="docs/screenshots/phone-sfx.png" width="250" alt="Sound FX mode on a phone">
</p>

## Running it

Play it in your browser at https://xsoc.github.io/chiptune-forge/ (deployed
from `main` on every push).

Or open the project in Godot 4.5 or later and press Play. Export presets for
Web, Linux, Windows, macOS and Android are included; see
[CONTRIBUTING.md](CONTRIBUTING.md) for building them.

## Using the Godot plugin

The plugin lives in `addons/chipforge/` and is also bundled in every export
zip. Copy that folder into your game, enable **Chiptune Forge** under
Project Settings > Plugins, and drop in your exported files: Godot imports
`.chipsong`, `.chipsfx` and `.chipkit` files as resources.

```gdscript
# Music: add a ChipMusicPlayer node and assign the song.
$Music.play()
$Music.intensity = 0.7          # adaptive: picks the Combat state
$Music.set_state("Boss")        # or choose a state directly
$Music.set_layer("Lead", "off") # or fade a single layer
$Music.transition_to("B", "bar")
$Music.bar.connect(func(i): print("bar ", i))

# Sound effects: add a ChipSfxPlayer node and assign the kit.
$Sfx.play("jump")
$Sfx.play("coin", 1.2)          # a little higher
```

The synth is pure GDScript, so the plugin works on every platform Godot
exports to, including the web, with nothing to compile. The file formats are
described in [docs/format.md](docs/format.md).

## Project layout

| Folder | What is in it |
|---|---|
| `addons/chipforge/` | The Godot plugin: resources, importers, synth and player nodes. MIT, self-contained. |
| `autoload/` | `AppState` (settings, current song, library) and `AudioService` (preview players). |
| `scenes/` | One scene per screen and per reusable control. |
| `scripts/generation/` | The generators. Plain `RefCounted` code with no scene dependencies. |
| `scripts/export/` | WAV, MIDI and zip export. |
| `scripts/targets/gameboy/` | Game Boy target: sound chip emulation, hUGEDriver player, arranger, SFX conversion and C writer. |
| `scripts/targets/nes/` | NES target: 2A03 emulation, a player that follows FamiStudio's sound engine, arranger, SFX conversion and the FamiStudio text writer. |
| `scripts/targets/sms/` | Master System target: SN76489 emulation, a player that writes PSGlib's register stream, arranger (built on the NES one), SFX conversion and the PSGlib, C and VGM writer. |
| `scripts/targets/genesis/` | Mega Drive target: YM2612 emulation (with the Master System's SN76489), FM patches, arranger, a frame-by-frame player, the VGM writer and SFX conversion. |
| `assets/gameboy/hUGEDriver/` | The vendored hUGEDriver source bundled with Game Boy exports. |
| `resources/` | Vibes, styles, SFX presets and chip profiles as `.tres` files, plus the theme. |
| `tests/` | Unit and golden-file tests. |
| `tools/` | Theme builder, screenshot tool, and the Game Boy, NES, Master System and Mega Drive checks CI runs. |

## Roadmap

Phase 1 is modern chiptune with no hardware limits. Phase 2 adds the Game Boy:
an arranger that fits songs to its four channels, an emulated sound chip for
previews, and C export for GBDK-2020 and hUGEDriver. CI builds example ROMs
from the export and checks that they play in the PyBoy emulator. Phase 3
adds the NES: the same arranger approach for its four melodic channels, an
emulated 2A03, and FamiStudio project export. CI opens the exported projects
in FamiStudio and has it write sound engine data, NSF, ROM and WAV files from
them. Then the Master System and Game Gear: the SN76489, exported as PSGlib
data. CI checks the data against PSGlib's own tools (vgm2psg, psgcomp and
psgdecomp) and compiles the C arrays with SDCC. Phase 4 brings the 16-bit
consoles, starting with the Mega Drive: CI converts the exported VGMs with
SGDK's xgmtool and checks the XGM keeps every register write, builds an
example ROM with SGDK, and compares the app's preview with libvgm's YM2612
playing the VGM and with the ROM running in Genesis Plus GX. The SNES and
PC Engine come next, and the last phase gives the modern synth several new
engines.

To build a Game Boy export yourself, unzip it, install
[GBDK-2020](https://github.com/gbdk-2020/gbdk-2020) and run
`make GBDK_HOME=/path/to/gbdk` in the `gameboy/` folder. The README inside
explains how to use the song and sounds in your own game.

To use an NES export, unzip it, open `nes/<name>.txt` in FamiStudio
(File > Import) and export from there, or use FamiStudio's command line as
`nes/README.txt` shows.

To use a Master System export, unzip it and add `sms/<name>_psg.c` to a
devkitSMS project (or `incbin` `sms/<name>.psg` in assembly), then call
`PSGPlay` once and `PSGFrame` every frame; `sms/README.txt` has the details.

To use a Mega Drive export, unzip it, put `genesis/<name>.vgm` and
`genesis/resources.res` in an SGDK project's `res/` folder and call
`XGM_startPlay(<name>)`; `genesis/main.c` is a complete example and
`genesis/README.txt` has the details.

## Licence

MIT, see [LICENSE](LICENSE). Bundled fonts are under the SIL Open Font
Licence; see [THIRD_PARTY.md](THIRD_PARTY.md).
