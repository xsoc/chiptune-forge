@tool
class_name Style
extends Resource
## A genre preset. A style sets the rhythm, form and instrument roles.

@export var id := ""
@export var display_name := ""
@export var group := ""
@export_multiline var description := ""
@export_group("Rhythm")
@export_range(40, 240) var tempo_min := 100
@export_range(40, 240) var tempo_max := 140
@export_range(2, 7) var beats_per_bar := 4
@export_range(0.0, 1.0) var swing := 0.0
## Drum pattern family, such as "rock", "four_floor" or "bossa".
@export var drum_pattern := "rock"
@export_range(0.0, 1.0) var drum_density := 0.5
@export_group("Parts")
## Relative weight of each bass pattern, such as {"root_8ths": 2, "octave": 1}.
@export var bass_patterns: Dictionary = {"root_8ths": 1.0}
## Relative weight of each accompaniment, from "arp", "chord_arp", "pad",
## "stabs" and "broken".
@export var accompaniment: Dictionary = {"arp": 1.0}
## Relative weight of each harmony line, from "thirds", "counter" and "echo".
@export var harmony_parts: Dictionary = {"counter": 1.0}
@export_range(0.0, 1.0) var melody_density := 0.5
@export_range(0.0, 1.0) var syncopation := 0.3
@export_group("Harmony")
@export var progression_weights: Dictionary = {"pop": 1.0}
## Extra weight added to the vibe's modes.
@export var mode_bias: Dictionary = {}
@export_range(0.0, 1.0) var chord_colour := 0.0
@export_group("Sound")
## Lead wave: "pulse", "saw", "triangle", "sine" or "" for the vibe's choice.
@export var lead_wave := ""
@export var bass_wave := "triangle"
@export var lead_glide := false
@export_group("Form")
## Relative weight of each song form.
@export var forms: Dictionary = {"verse_chorus": 1.0}
