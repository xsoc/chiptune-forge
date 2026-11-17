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

#### Synth engines

`engine` picks how the plugin makes the sound. Without it (or with `chip`)
the keys above are all there is. The other engines add their own keys, and
the envelope, vibrato, glide, arpeggio and echo keys still apply:

| `engine` | Keys |
|---|---|
| `analog` | Two oscillators (`wave` `saw`, or `pulse` with `duty`) detuned by `detune` cents, through a resonant low-pass filter: `cutoff` (Hz at middle C), `resonance` (0 to 0.92), `key_track` (how far the cutoff follows the pitch, 0 to 1), and a filter envelope that starts `env_amount` octaves up and falls over `filter_decay` seconds. |
| `fm` | A sine carrier and a sine modulator at `ratio` times its pitch. The index starts at `index` and falls to `index_end` over `index_decay` seconds; `feedback` (0 to 1.5) feeds the modulator back into itself. |
| `wavetable` | A sweep through `bank` (`bright`, `soft`, `vocal` or `metal`, eight waves each) from position `wt_from` to `wt_to` (0 to 1) over `wt_time` seconds. |
| `sampled` | `sample`: `pluck`, `epiano`, `strings`, `brass`, `bell`, `kick`, `snare`, `hat`, `open_hat`, `crash` or `tom`, played at the note's pitch (drums ignore it, toms follow it a little). `strings` and `brass` loop while the note is held. |

The plugin makes the banks and samples from maths the first time they are
used, so nothing is downloaded or recorded, and they are the same on every
platform. An instrument that has an engine may also hold a `chip` object:
the chip settings the engine replaced, which the console targets use.

## `.chipsfx` (format `chipforge-sfx`, version 1)

```json
{
  "format": "chipforge-sfx",
  "version": 1,
  "meta": {"name": "Coin", "preset": "coin", "seed": 1234, "variant": "Classic", "license": "..."},
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

`meta.variant` names the preset baseline the seed picked ("Classic" for the
preset's base, or one of its `variants`, such as "No arpeggio"). It is
informational: `params` alone defines the sound.

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

## NES export

NES exports are not a Chiptune Forge format either: they are
[FamiStudio](https://famistudio.org) text projects, the format FamiStudio's
File > Export > FamiStudio Text writes and File > Import reads. They are
written without a version attribute, so any current FamiStudio opens them.

A song export's `nes/<name>.txt` holds one song on the four 2A03 channels
(Square1, Square2, Triangle, Noise; DPCM is left empty) in FamiStudio's tempo
mode. One row is one 16th-note step; the groove (for example `7-6`) is the
number of video frames each row lasts, chosen to match the song's BPM within
about 2%. Patterns break at sections and every bar. Instruments use volume,
arpeggio, pitch and duty envelopes only; chords play as looping arpeggios;
drums are noise instruments with short envelopes. Every note on the pulse and
noise channels sets its volume, since FamiStudio's volume column is sticky.

A sound kit export's `nes/<kit>.txt` holds one song per sound, each a single
note of an instrument whose envelopes carry the sound frame by frame (volume,
semitone offset from the first note, and duty or noise mode) at one frame
per row. FamiStudio's sound effect export turns these into data for
`famistudio_sfx_play`.

## Master System export

Master System and Game Gear exports are [PSGlib](https://github.com/sverx/PSGlib)
data, the format PSGlib's `PSGPlay` and `PSGSFXPlay` read (in devkitSMS and in
the Z80 assembly version alike). The data is a stream of SN76489 port writes:

| Bytes | Meaning |
|---|---|
| `$80`-`$FF` | A latch byte, written to the chip as it is. |
| `$40`-`$7F` | A data byte for the last latched register (bit 6 is set and ignored by the chip). |
| `$38`-`$3F` | Wait 1 to 8 frames. |
| `$01` | Loop point. |
| `$00` | End of data. |

The data is uncompressed (PSGlib's `psgcomp` compresses it). Each frame
writes only the registers that changed, in the order PSGlib's `vgm2psg`
writes them (for each tone channel its period then its volume, then the
noise). At the loop point every register is written again, so the loop
sounds the same however the song ended.

A song export's `sms/` folder holds `<name>.psg`, the same bytes as a C array
in `<name>_psg.c` and `<name>_psg.h` (`<name>_psg` and `<name>_psg_size`), and
`<name>.vgm`, a VGM 1.50 file of the same register writes at 60 frames a
second. Square 1 plays the lead, Square 2 the accompaniment, Square 3 the bass
(the chip's lowest note is A2, so bass lines usually move up an octave) and
the noise channel the drums on its three fixed rates.

A sound kit export's `sms/` folder holds one `.psg` and one `.vgm` per sound,
and all of them as C arrays in `<kit>.c` and `<kit>.h`. Each sound writes only
its own channel: Square 3 (`SFX_CHANNEL2` in PSGlib) for tonal sounds, the
noise channel (`SFX_CHANNEL3`) for noisy ones.

## Mega Drive export

Mega Drive / Genesis exports are VGM 1.60 files for
[SGDK](https://github.com/Stephane-D/SGDK), whose resource compiler converts
them to music for its XGM driver (`XGM name "file.vgm"` in a `.res` file).
The VGM holds the YM2612 (clock 7,670,453 Hz) and SN76489 (3,579,545 Hz)
register writes the song makes, one frame at a time with a 1/60 s wait
(command `0x62`) after each, which is the form XGM's converter expects.
Each frame writes only the registers that changed. A new FM note loads its
patch if the channel holds another one, sets the pitch (`$A4` then `$A0`),
and keys the channel off and on; a note's end keys it off so the patch's own
release plays. At the loop point every patch and register is written again.
A GD3 tag carries the title.

The arrangement: FM 1 plays the lead, FM 2 the harmony, FM 3 the arpeggio,
FM 4 the bass and FM 5 the kick, snare and toms; Square 1 to 3 play the pad's
chords (up to three notes) and the noise channel the snare, hats and
cymbals. FM 6 is left free because XGM plays samples there. Each FM part's
patch is picked from its wave in the source song (`scripts/targets/genesis/md_patches.gd`).

A song export's `genesis/` folder holds `<name>.vgm`, `resources.res` (the
resource line) and `main.c` (a minimal SGDK program that plays it). A sound
kit export's `genesis/` folder holds one 8-bit mono WAV at 14 kHz per sound
(XGM's sample format) and `resources.res` with a `WAV name "file.wav" XGM`
line for each; `README.txt` shows `XGM_setPCM` and `XGM_startPlayPCM`.

## SNES export

SNES exports are Impulse Tracker modules for SNESMod, the sound driver in
[PVSnesLib](https://github.com/alekmaul/pvsneslib), whose `smconv` tool turns
them into a soundbank. The module follows SNESMod's rules: instrument mode
with one sample per instrument (every note maps to it), at most 64 patterns
and 199 orders, 16-bit signed samples whose loops are whole 16-sample BRR
blocks, and only the effects SNESMod plays. Notes are Impulse Tracker note
numbers, which are MIDI notes (C-5, note 60, is middle C); each sample's
C5 speed plays its intended pitch at note 60. Rows use:

| Column | Use |
|---|---|
| Note | A note with its instrument and volume (0 to 64); `===` (note off) where a note ends before the next. |
| `Axx` | Not used: the header's initial speed and tempo set the timing. |
| `Bxx` | On the last row, channel 8: jump to the loop's first order. |
| `Hxy` | The lead's vibrato, from a beat into long notes. |
| `Jxy` | Arpeggios: the note, then x and y semitones above, one per tick. |

Instruments carry a volume envelope (ticks, levels 0 to 64) with a sustain
node, held until the note off. The song message holds SNESMod's echo
commands after a `[[SNESMOD]]` line (`edl`, `efb`, `evol`, `efir`, `eon`).
SNESMod ticks `8000 / floor(20480 / tempo)` times a second, about 2% slower
than Impulse Tracker's `tempo * 2 / 5`, so tempos are picked for SNESMod.

The arrangement: voice 1 plays the lead, 2 the harmony, 3 the arpeggio, 4
the bass, 5 and 6 the pad's two highest notes and 7 all the drums as
samples. Voice 8 is left free: SNESMod plays sound effects there. Samples
are made by `scripts/targets/snes/snes_samples.gd` (single-cycle waves,
detuned pads and drums); their BRR encodings are in `assets/snes/samples/`,
written by `tools/snes_samples.gd` with a port of smconv's encoder, so the
preview plays the bytes smconv will produce.

A song export's `snes/` folder holds `res/<name>.it`, a `Makefile` and a
`main.c` that build a ROM playing it with PVSnesLib 4.7 or later. A sound kit
export's `snes/` folder holds one BRR file per sound (16 kHz, SNESMod's sound
effect pitch 4) and `data.asm`, which puts them in the ROM between labels;
`README.txt` shows `spcAllocateSoundRegion`, `spcSetSoundEntry` and
`spcPlaySound`.

## PC Engine export

PC Engine exports are data for Chiptune Forge's own player,
`pce_player.c`, which is MIT-licensed C for
[HuCC](https://github.com/pce-devel/huc). A song plays on all six PSG
channels: lead, harmony, arpeggio, bass, the pad's top note and drums (noise
for snares, hats and cymbals; a falling sine for kicks and toms). The data
format, a header, waveforms, instruments with volume, arpeggio and pitch
envelopes, and one command stream per channel, is described at the top of
`pce_player.c`. The app's preview (`PcePlayer`) writes the PSG's registers
exactly as the player does, which the tests check frame by frame against a
GDScript copy of the player (`PceDriver`).

A song export's `pce/` folder holds `song.bin`, `pce_player.c`, a `main.c`
that plays the song and a `Makefile`. A sound kit export's `pce/` folder
holds `sfx.bin` and the player; sounds play on channel 5, which the music
gets back when a sound ends.

## MSX and ZX Spectrum 128 export

MSX and Spectrum exports are data for Chiptune Forge's own player,
`ay_player.asm`, which is MIT-licensed Z80 assembly (Pasmo syntax) for the
AY-3-8910 on both machines. A song plays on the chip's three channels: A the
lead, B the accompaniment, C the bass, and the drums borrow B's noise for as
long as each hit sounds. The data is the chip's registers 0 to 10 frame by
frame at 50 Hz: each frame writes the registers that changed, and repeated
stretches play earlier ones again through a call command. The format is
described at the top of `ay_player.asm`. `song_msx.bin` and `song_zx.bin`
differ only in tone periods (the chips' clocks differ by about 1%). On a
60 Hz MSX, `ay_interrupt` skips every sixth interrupt.

The app's preview (`AyPlayer`) sets the registers that the data holds; the
tests decode the data as the player does and check every frame, and CI runs
the assembled player in a small Z80 emulator (`tools/ay_check.py`) and
compares the registers it writes on every frame.

A song export's `msx/` folder holds both songs, `song.vgm`, the player,
`msx_main.asm` (an MSX cartridge), `zx_main.asm` (a Spectrum 128 tape) and a
`Makefile`. A sound kit export's `msx/` folder holds `sfx_msx.bin`,
`sfx_zx.bin` and the player; sounds play on channel B, which the music gets
back when a sound ends.

The planned Arkos Tracker 2 export was replaced by this player: its `.aks`
format is not documented, and the data here can be checked end to end.

## Game Boy Advance export

Game Boy Advance exports are Impulse Tracker modules for
[Maxmod](https://maxmod.org), devkitPro's sound library, which mixes
sampled channels into the GBA's two Direct Sound PCM channels. The
arrangement is the SNES one (lead, harmony, arpeggio, bass, two pad voices
and drums on sampled instruments, channel 8 left free for sound effects),
with 8-bit samples, no echo, and ticks at Impulse Tracker's own rate
(tempo x 0.4 a second), as Maxmod plays them. The preview (`GbaPlayer`, on
`GbaMixer`) follows the same row logic as the SNES preview and mixes the
way Maxmod does: nearest-sample playback of 8-bit samples at 16 kHz.

A song export's `gba/` folder holds `audio/<name>.it`, a `Makefile` (mmutil
builds the soundbank, devkitARM links libgba and Maxmod) and a `main.c` that
plays the song. A sound kit export's `gba/audio/` folder holds one 8-bit,
16 kHz WAV per sound for the same soundbank, played with `mmEffect`.

## Commodore 64 export

Commodore 64 exports are PSID files (`.sid`) holding Chiptune Forge's own
player, `sid_player.s` (MIT-licensed 6502 assembly for ca65, assembled at
$1000 as `sid_player.bin`), with the song after it: init at $1000, play at
$1003, 50 times a second (PAL). Any SID player plays them, and games load
them like other SID music. Voice 1 plays the lead, voice 2 the
accompaniment, voice 3 the bass, and the drums borrow voice 2's noise for as
long as each hit sounds. The SID has no per-voice volume, so every NES
volume envelope becomes the closest hardware ADSR envelope, and each new
note turns its gate off for one frame so the envelope restarts.

The data is the SID's 25 registers frame by frame, in the same register
stream format as the MSX player (each frame writes what changed; repeats
play earlier stretches through a call command), described at the top of
`sid_player.s`. The app's preview (`SidPlayer`) sets the registers that the
data holds; the tests decode the data and check every frame, and CI runs
the player in a small 6502 emulator (`tools/sid_check.py`) and compares the
registers it writes on every frame, with and without sound effects, then
compares sidplayfp playing the PSID with the preview.

A song export's `c64/` folder holds the `.sid`, `song.bin`, the player
(source, binary and ld65 config), an example program (`main.s`, `main.cfg`)
and a `Makefile`. A sound kit export's `c64/` folder holds `sfx.bin` and the
player; sounds play on voice 2 ($1006 with the sounds' address in A/X, then
$1009 with the sound's number), which the music gets back when a sound ends.

## DOS PC export

The DOS PC target plays and exports for one sound card at a time: the PC
speaker (1981), the Tandy 1000 (1984), the AdLib (1987) and Sound Blaster
(1989), both a Yamaha YM3812 (OPL2), the Sound Blaster Pro (two OPL2s, one
per speaker), the Sound Blaster 16 (a YMF262, the OPL3), and the MIDI
modules: the Roland MT-32 (1987) and Roland's Sound Canvas (1991), and the
Gravis Ultrasound (1992).

For the FM cards the arranger starts from the Mega Drive arrangement
and gives each part a two-operator FM patch: on an OPL2 six melodic
channels (lead, harmony, arpeggio, bass and two for the pad's chords) and
the rhythm mode's five drums. The Sound Blaster Pro's second chip doubles
the lead and bass and adds a third pad note, and the OPL3 pans the parts
and uses its extra waveforms. The music driver runs at 70 Hz, as most DOS
music did, and the tempo is fitted to it.

The app's preview (`OplPlayer` writing to `Opl`, our MIT-licensed GDScript
emulation of the OPL2 and OPL3) writes the chip's registers each frame,
and the exports record those writes:

| File | What it is |
|---|---|
| `pc/<name>.wlf` | IMF type 1 at 700 Hz (OPL2 cards only), the format id Software's games and many DOS engines play. |
| `pc/<name>.dro` | DOSBox Raw OPL v2, which DOSBox captures and many players and trackers read. |
| `pc/<name>.vgm` | VGM 1.51 for the YM3812 (two of them for the Sound Blaster Pro) or the YMF262. |

CI plays every file with AdPlug's DOSBox OPL core and checks its loudness
follows the app's preview.

The PC speaker is one square wave from the timer chip, on or off. Its
arranger keeps the NES arrangement's lead, bass and drums; the driver runs
at 70 Hz and plays two tones a frame, each 1/140 s, so while the lead and
bass both sound they take turns, and a drum hit takes over (noise as random
pitches, kicks and toms as a falling tone). The export is the speaker's
pitch as one 16-bit PIT divisor per 1/140 s (0 is silence), as a C header
and as a binary file, with `speaker.c`, an MIT-licensed player for Open
Watcom or Turbo C that runs the timer at 140 Hz, keeps the BIOS clock right
and plays a sound effect over the music, and an example program. CI builds
it with Open Watcom.

The Tandy 1000's SN76496 is the Master System's chip with different white
noise, so the Tandy uses the Master System arrangement and exports VGM
files (with the SN76496's noise settings in the header), which CI plays
with libvgm and compares with the preview.

The Roland MT-32 and the Sound Canvas (General MIDI) are MIDI sound
modules, so their export is a MIDI file set up for the module: each part
gets the closest program (the MT-32's own presets, or General MIDI's), its
volume, pan and effect sends, and its own channel (on the MT-32, parts 1 to
8 on channels 2 to 9 and the rhythm part on 10, as it starts up). SysEx at
the start sets the module up: on the MT-32 the reverb, each part's partial
reserve, the MIDI channels and a message on its display, with Roland
checksums; on the Sound Canvas GM System On and a GS reset. A beat of
silence follows while the module takes it. Pad chords are cut when the
song would need more than the module plays at once (32 partials on the
MT-32, about two a note; 24 voices on the Sound Canvas). Neither module is
emulated: the preview plays the song on the app's own sampled and analog
engines, picked to match each program, with a little room echo. CI plays
both files with FluidSynth to check they follow the song.

The Gravis Ultrasound's GF1 chip plays up to 32 voices of 16-bit samples
from its own memory, interpolated, with 16 pan positions. Its arranger is
the SNES one (lead, harmony, arpeggio, bass, two pad voices and drums on
the app's generated sampled instruments) at Impulse Tracker's tick rate
with no echo, and the export is an Impulse Tracker module with 16-bit
samples, which Impulse Tracker and the DOS sound systems games used play on
a GUS directly. The preview (`GusMixer`) plays the samples as the GF1 does;
CI renders the module with libopenmpt and compares it with the preview.

Sound effects on the Sound Blasters are samples for the card's DAC:
Creative Voice files (`.voc`, 8-bit) at 11 kHz on the Sound Blaster and
22 kHz on the Pro, and 16-bit 22 kHz WAVs on the 16. The AdLib has no DAC,
so its effects are FM on channel 2 (the harmony's, which the music gets
back when a sound ends), exported as DRO and IMF files of the register
writes. The MIDI modules play music only; DOS games played their sounds on
a Sound Blaster beside them, so those cards export 22 kHz VOC files. The
GUS's sounds are 16-bit WAVs for voices the music leaves free.

## Game Boy export

Game Boy exports are not a Chiptune Forge format: they are C source for
[GBDK-2020](https://github.com/gbdk-2020/gbdk-2020), laid out the way
hUGETracker's "GBDK .c" export lays it out, so they work with any game that
already uses [hUGEDriver](https://github.com/SuperDisk/hUGEDriver).

A song export's `gameboy/` folder holds:

| File | What it is |
|---|---|
| `src/song_<name>.c` | Patterns (`DN(note, instrument, effect)` rows, at most 64 per pattern), orders, instruments and waves, and the `hUGESong_t` descriptor. |
| `src/song_<name>.h` | `extern const hUGESong_t song_<name>;` plus `SONG_<NAME>_TMA` and `_TAC` (the timer settings that give the song's tempo) and `SONG_<NAME>_SFX_CHANNEL` (the channel sound effects may interrupt, as `HT_CH2` or `HT_CH4`, or `-1`). |
| `src/main.c` | An example that plays the song from the timer interrupt. |
| `src/cf_sfx.c`, `cf_sfx.h` | The sound effect player, when a channel is reserved. |
| `hUGEDriver/` | The driver source and, in release builds, `lib/hUGEDriver.lib` prebuilt for GBDK. |
| `Makefile`, `README.txt` | Build with `make GBDK_HOME=/path/to/gbdk`. |

The driver runs from the timer rather than VBlank, so the tempo can match the
song's BPM closely (within about 1%). Each row of the arranged song is one
16th-note step.

Sound kit exports hold `src/<kit>.c` and `.h` with one `cf_sfx_t` per sound
(`SFX_JUMP` and so on), the `cf_sfx` player and an example ROM that plays
each sound. A sound is one register update per frame on Pulse 2 or the noise
channel: three bytes per frame (volume, retrigger flag and duty; then the
period, or the NR43 value for noise). Call `cf_sfx_play(&SFX_JUMP)` to start
one and `cf_sfx_update()` once a frame. While a sound plays, `cf_sfx` mutes
that channel in hUGEDriver and unmutes it when the sound ends.
