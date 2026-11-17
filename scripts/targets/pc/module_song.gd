class_name ModuleSong
extends RefCounted
## A song set up for a MIDI sound module: the Roland MT-32 or a General MIDI
## module such as the Roland Sound Canvas. The notes are the song's own;
## what changes is which part plays on which MIDI channel with which
## program, the SysEx that sets the module up, and chords trimmed to the
## module's polyphony. [ModuleArranger] makes one; [method midi_bytes]
## writes it. The preview ([member preview]) is an approximation on the
## app's own synth engines: neither module is emulated.

var card := "mt32"
var title := "song"
## The song, as the arranger was given it.
var source: ChipSong
## The song on sampled and analog engines chosen to sound like the module's
## programs, with its reverb, for previews.
var preview: ChipSong
## {channel index: {midi, program, program_name, volume, pan, reverb,
## chorus, setup_tick}}. Channels left out are not played.
var parts := {}
## {channel index: most notes of a chord}.
var chord_limit := {}
## Whole SysEx messages, sent first.
var sysex: Array = []
## Ticks (at [constant MidiWriter.PPQ] per beat) after the SysEx before the
## music starts.
var lead_in := 0
## The most partials (MT-32) or voices (General MIDI) sounding at once.
var peak := 0
var report: PackedStringArray = []


func midi_bytes() -> PackedByteArray:
	return MidiWriter.encode_setup(source, {"parts": parts, "sysex": sysex, "lead_in": lead_in, "chord_limit": chord_limit})


func get_bpm() -> float:
	return source.get_bpm()
