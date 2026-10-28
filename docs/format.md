# File formats

All three formats are UTF-8 JSON. Readers must ignore keys they do not know,
so later versions can add fields without breaking older plugins. A file
whose `version` is higher than the reader supports is rejected.

The extensions are `.chipsong`, `.chipsfx` and `.chipkit`. (The plan said
`.chipsong.json`, but Godot importers match only the last extension, so a
double extension would be imported as plain JSON.)

## `.chipsong` (format `chipforge-song`, version 1)

| Key | Meaning |
|---|---|
| `format`, `version` | `"chipforge-song"`, `1` |
| `meta` | Title, `seed`, the full generator `settings`, `key`, `form`, `target`, `engine_version` and the `license` note. Not needed for playback. |
| `timing` | `bpm`, `beats_per_bar`, `steps_per_beat` (4 means a step is a 16th note), `swing` (0 to 1), `loop`, and `loop_start` / `loop_end` in steps. |
| `effects` | Song-wide echo: `echo` (send level), `echo_beats` (delay), `echo_feedback`. |
| `instruments` | Array of instruments. See below. |
| `channels` | Array of `{name, instrument, layer, volume, pan, polyphony}`. `instrument` indexes `instruments`. |
| `patterns` | Array of `{notes: [...]}`. Patterns are shared between sections. |
| `sections` | Array of `{name, length, patterns, energy, chords}`. `length` is in steps. `patterns` holds one pattern index per channel, or `-1` for silence. `chords` is `[[step, "numeral"], ...]`, for display. |
| `order` | Section indexes in play order. |
| `layers` | `[{name, channels: [...]}]`: the named groups the adaptive system fades. |
| `states` | `[{name, min_intensity, levels: {layer: level}}]`. A level is `"off"`, `"low"`, `"mid"`, `"full"` or a number from 0 to 1. |
| `cues` | `[{name, step}]`, absolute steps from the song start. Includes `section:<name>`, `loop_start` and `loop_end`. |

### Notes

Each note is an array: `[step, length, pitch, velocity, instrument?, arp?]`.

- `step` is relative to the start of the section, and `length` is in steps.
- `pitch` is a MIDI note number, `velocity` is 1 to 127.
- `instrument` (optional) overrides the channel's instrument for this note.
  Drum channels use it to pick kick, snare, hats and so on.
- `arp` (optional) is an array of semitone offsets cycled at the
  instrument's `arp_rate`, for chip-style chord arpeggios.

### Instruments

`wave` is `pulse` (or `square`), `triangle`, `saw`, `sine`, `noise` or
`wave` (a wavetable given in `table`). Other keys, all optional:
`duty` (pulse width, 0 to 1), `attack`, `decay`, `release` (seconds),
`sustain` (level), `volume`, `vibrato_depth` (semitones), `vibrato_rate` (Hz),
`vibrato_delay` (seconds), `glide`, `arp_rate` (Hz), `pitch_drop`
(semitones, for drums) with `pitch_drop_time`, `steps` (pitch quantising
for a stepped, NES-style triangle), `short` (short-period noise) and `echo`
(send level).

## `.chipsfx` (format `chipforge-sfx`, version 1)

```json
{
  "format": "chipforge-sfx",
  "version": 1,
  "meta": {"name": "Coin", "preset": "coin", "seed": 1234, "license": "..."},
  "params": {"wave": "square", "base_freq": 0.55, "sustain": 0.07, "decay": 0.33}
}
```

`params` follows the sfxr model: values are mostly 0 to 1 (ramps are -1 to
1), and missing keys take the defaults in
`addons/chipforge/runtime/chip_sfx_synth.gd`. Extras beyond sfxr are the
`triangle` and `noise_short` waves, `crush`, `echo` and `echo_delay`, and
`noise_seed` so noise renders identically everywhere. An optional `layer2`
at the top level holds a second parameter set mixed on top, for sounds such as explosions
with a thump under the noise.

## `.chipkit` (format `chipforge-kit`, version 1)

```json
{
  "format": "chipforge-kit",
  "version": 1,
  "name": "My kit",
  "sounds": [{"id": "jump", "sound": { ...a .chipsfx object... }}]
}
```

`id` is what `ChipSfxPlayer.play()` takes. Console exports use the upper-case
form, `SFX_JUMP`.
