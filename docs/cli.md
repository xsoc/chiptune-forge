# Command line

Chiptune Forge runs without a window, so music and sound effects can be made
from scripts, build pipelines and CI. The command line uses the same engine,
settings and seeds as the app, so the same settings give the same files.

```
chiptune-forge --headless -- generate --vibe happy --style platformer --seed 1234 --out build/music
godot --headless --path . -- generate ...          # from a checkout of this repository
docker run --rm -v "$PWD:/work" chiptune-forge generate ...
```

Godot passes everything after `--` to the app. The desktop builds (Windows,
macOS, Linux) and the Docker image have the command line; the web and phone
builds do not. Audio renders offline, so no sound card is needed
(`--audio-driver Dummy` works on servers, and the Docker image uses it).
Relative paths start from the folder you run the command in.

## Commands

| Command | What it does | Example |
|---|---|---|
| `generate` | Makes a song from flags or a settings file and exports it | `generate --vibe happy:70 --vibe cozy:30 --style platformer --target gameboy --seed 1234 --out build/music` |
| `sfx` | Makes sound effects from presets, with variants | `sfx --preset jump --preset coin --variants 5 --target nes --out build/sfx` |
| `export` | Exports a saved project again, for another target or format | `export level1.cforge --target nes --format console` |
| `batch` | Runs a manifest of jobs | `batch music.manifest.json` |
| `validate` | Checks a file against its format and a target's limits | `validate theme.chipsong --target snes --strict` |
| `list` | Lists vibes, styles, targets, presets, formats, packs, modes, keys or structures | `list vibes --json` |
| `version` | Prints the app, engine and file format versions | `version` |

`help` (or no command) prints a summary of everything here.

### generate

These flags match the Generate screen:

| Flag | Values |
|---|---|
| `--vibe id[:strength]` | Up to three, each with a blend strength from 1 to 100 (default 100). `list vibes` shows the ids. |
| `--style id` | `list styles` shows the ids. |
| `--target id` | `modern` (default), `gameboy`, `nes`, `sms`, `genesis`, `snes`, `pce`, `gba`, `msx`, `c64`. |
| `--intensity`, `--complexity` | 0 to 100. |
| `--tempo` | `auto` or 40 to 240 BPM. |
| `--key` | `auto` or a note name: C, F#, Bb and so on. |
| `--mode` | `auto` or a mode: `list modes`. |
| `--length` | Seconds, or minutes and seconds as `1:30`. |
| `--structure` | `auto`, `loop`, `verse_chorus`, `aaba`, `rondo`, `through`, `build`, `boss` or `jingle`. |
| `--energy` | `flat`, `build`, `wave` or `peak_drop`. |
| `--loop`, `--no-loop`, `--intro`, `--no-intro`, `--outro`, `--no-outro` | Song form switches. |
| `--seed` | A number or a word. Without it the command picks one and prints it, so a run can always be repeated. |
| `--settings file.json` | Loads every setting from a JSON file: a `.cforge` project, or an object like a project's `settings`. Flags override it. |

Every song has its adaptive layers and states, so `--layers` is accepted and
changes nothing.

### sfx

`--preset id` (repeat it for more sounds; `list presets` shows the ids),
`--variants n` (1 to 50 takes of each preset, from consecutive seeds),
`--seed`, `--target`, and `--name` for the kit.

### Output

| Flag | Meaning |
|---|---|
| `--out folder` | Where files go (default: the current folder). The layout is the same as the app's export zip: `godot/`, `audio/`, `midi/`, the target's folder (such as `nes/`), a README and the project file. |
| `--name prefix` | File name and C symbol prefix (default: the song's title, or `sounds` for a kit). |
| `--format list` | Comma-separated, from `json` (files for the Godot plugin), `plugin` (the plugin itself), `wav`, `stems` (one WAV per layer), `midi`, `console` (the target's source, data and example project; `c` and `asm` mean the same) and `project` (a `.cforge` file to export again later). `all` means every one. The default is `json,plugin,wav,console,project`. |
| `--loops n` | How many times a song's WAV plays the loop. |
| `--json` | Prints a machine-readable report instead of the summary. |
| `--strict` | Fails with exit code 2 when the music is over a chip's limits, or when the arranger had to drop parts, move notes or merge drums to fit. |
| `--pack file.chippack` | Uses a [community pack](../packs/README.md) for this run. Packs added in the app are always available. |

The JSON report holds the files written, the seed, the settings, and the
target's report: whether it fits, whether the arranger changed the music,
and each line of the report the Export screen shows (data size against the
target's budget among them).

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad arguments |
| 2 | Over a chip's limits, or the music had to change (only with `--strict`) |
| 3 | A file could not be read or written |
| 4 | A file is not a valid song, sound, kit, project, pack or manifest |

## Projects

Every export, from the app or the command line, includes a `.cforge`
project: the settings, the seed and the song's notes (with any edits from the
note editor), or a kit's sounds, and the target. `export` reads it, so one
saved project can be exported again to any target. `export` and `validate`
also take `.chipsong`, `.chipsfx` and `.chipkit` files, and `validate`
checks `.chippack` packs.

## Batch manifests

A manifest lists jobs, each with its own settings, seed, formats and output
folder, so one file can make every track and sound in a game, and the audio
can live in version control as settings and seeds rather than binaries.

```json
{
	"jobs": [
		{"command": "generate", "name": "title_theme", "vibe": ["heroic:70", "happy:30"], "style": "platformer",
		 "seed": "title", "target": "nes", "format": "console,wav,project", "out": "build/audio/title"},
		{"command": "sfx", "name": "game_sounds", "preset": ["jump", "coin", "hurt"], "seed": 7,
		 "target": "nes", "out": "build/audio/sfx"},
		{"command": "export", "file": "saved/level1.cforge", "target": "gameboy", "out": "build/audio/level1"}
	]
}
```

Each job takes the command's flags as keys without the dashes. Repeated
flags are lists, and switches are `true`. Paths are relative to the manifest.
`--strict` and `--json` on the batch apply to every job, and the exit code
is the worst job's. [examples/cli](../examples/cli) has a manifest and an
example GitHub Actions workflow that runs it with the Docker image, then
builds the NES example projects.
