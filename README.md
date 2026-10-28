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
- **Seeds.** The same settings and seed always give the same song, on every
  platform.

Everything you make is yours, for any use, with no royalties or credit
required.

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
| `resources/` | Vibes, styles, SFX presets and chip profiles as `.tres` files, plus the theme. |
| `tests/` | Unit and golden-file tests. |
| `tools/` | Theme builder and screenshot tool. |

## Roadmap

Phase 1 (this release) is modern chiptune with no hardware limits. Next come
the console targets from the plan: Game Boy, then NES and Master System, with
exports that fit each chip's channels.

## Licence

MIT, see [LICENSE](LICENSE). Bundled fonts are under the SIL Open Font
Licence; see [THIRD_PARTY.md](THIRD_PARTY.md).
