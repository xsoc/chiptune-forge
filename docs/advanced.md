# Advanced mode

The Advanced screen (Music mode) edits a song from single notes up to its
sections. It works on the song you generated, or on a blank one ("New blank
song" in the Song panel keeps the instruments and starts with one silent
four-bar section). Every change can be undone (Ctrl+Z) and redone
(Ctrl+Shift+Z or Ctrl+Y), is kept when the song is saved to the library, and
locks the part it changes so Regenerate leaves it alone. Changes to the
sections lock every part. Generating a new song replaces the edits; Undo
brings them back.

The three panels at the top show or hide with **Song**, **Edit** and
**Live**. Phones start with only the piano roll and the keys.

## Notes

The piano roll shows one part of one section. Pick the part at the left of
the tool row and the section in the Song panel. Other parts' notes in the
section show faintly behind it.

| Tool | Mouse or touch |
|---|---|
| Draw | Tap an empty cell to add a note of the chosen length; drag to make it longer or shorter. Drag a note to move it, drag its right end to change its length, tap it to remove it. |
| Select | Tap a note (Shift or Ctrl adds to the selection) or drag a box. Drag a selected note to move all of them, or its right end to stretch them. |
| Erase | Remove every note you touch. |

A right click erases with any tool. Tap a key on the left to hear the note.
Drag on the velocity lane to set how hard notes play. Two fingers pan and
pinch to zoom; the mouse wheel scrolls (Shift scrolls sideways, Ctrl zooms).
With the roll focused, arrow keys move the selection (Shift+Up/Down by an
octave), Delete removes it and Ctrl+A selects everything.

Parts that play one note at a time (lead, harmony, arp, bass) stay that
way: a note cuts the one before it short. The pad plays chords of up to
three notes; the editor warns if a part has more notes at once than its
channel plays.

Sections can share a part's notes (the generator reuses patterns, and
Repeat plays a section again). An edit then changes every section that
plays them, which the tool row says; "Edit only here" gives the section its
own copy.

## Bars

Drag across the bar numbers above the roll to pick bars (tap a picked bar to
let go). The Edit panel works on the selected notes, else the picked bars,
else the whole section: Copy (Ctrl+C), Paste at the picked bar or the cursor
(Ctrl+V), Duplicate to just after (Ctrl+D), Clear, transpose by a semitone or
an octave, and Quantize to the grid.

## Sections and the song

The Song panel lists the sections in play order; tap one to edit it.

- **New** adds a silent section after it, **Copy** adds a copy with its own
  notes, **Repeat** plays the same section again.
- **Remove** takes it out of the order; **<** and **>** move it.
- The name box renames it and the bars box sets its length (notes past the
  end are dropped; a section that shared them keeps its own).
- **Loop from here** and **Loop to here** set the song's loop, which the
  game player and every export use. Sections in the loop are tinted.
- Tempo and swing apply to the whole song.

**Play section** (Space) plays from the start of the section; with **Loop
section** on, playback loops just that section.

## Live playing and recording

Play the part on the on-screen keys (several fingers make chords; drums get
pads), on the computer keyboard (Z to M for one octave with S, D, G, H, J as
the black keys, Q to I for the next with 2, 3, 5, 6, 7), or on a MIDI
keyboard after **Connect MIDI**. MIDI works on Windows, macOS and Linux, and
in browsers with Web MIDI (Chrome, Edge and Firefox, which ask first). Godot
has no MIDI input on phones, so they use the on-screen keys. Drums follow
the General MIDI drum map (36 kick, 38 snare, 42 hat, 46 open hat, 45 tom,
51 ride, 49 crash); other notes pick a drum by their place in the octave.

**Record** plays the song from the section (after a bar of clicks with
**Count in**) and records what you play into the part until you press it
again. Notes are timed by what you hear, so the output delay is taken off,
and snap to the grid. **Add to notes** layers the take over what is there;
**Replace notes** removes the notes the take passed over. With Loop section
on, each pass adds to the same section, like a looper. **Click** plays a
metronome while recording.

**Step input**: while the song is stopped, each note you play goes in at
the cursor (tap an empty cell with the Select tool to place it) with the
chosen length, and the cursor moves on. On the pad and drums, notes played
together make a chord.

## Targets

Edited songs are ordinary songs: they play through the song's synth (or the
chip preview for a console target) and every export arranges them for the
target's channels, as it does generated songs. The line under the editor
shows the target's report, the same as on the Export screen.
