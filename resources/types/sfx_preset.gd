@tool
class_name SfxPreset
extends Resource
## A sound effect preset. Each press of the preset rolls a new variation:
## the seed picks one baseline (the base, or one of [member variants]), then
## adds a random amount within [member ranges].

@export var id := ""
@export var display_name := ""
@export var group := ""
@export_multiline var description := ""
## Synth parameters (see ChipSfxSynth.DEFAULTS).
@export var base: Dictionary = {}
## Random spread per parameter: name to [min, max] added to the base value.
@export var ranges: Dictionary = {}
## Waves to choose from. Empty keeps the base wave.
@export var waves: PackedStringArray = []
## Optional second layer, mixed with the first.
@export var layer2: Dictionary = {}
@export var layer2_ranges: Dictionary = {}
## Other baselines for the same sound, each built differently (an extra
## arpeggio, another wave, a phaser and so on). Each is a dictionary with a
## "name", "base" overrides merged over [member base], and optional "ranges"
## merged over [member ranges] and "waves" that replace [member waves].
@export var variants: Array[Dictionary] = []
