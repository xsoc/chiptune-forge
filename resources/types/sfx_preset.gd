@tool
class_name SfxPreset
extends Resource
## A sound effect preset. Each press of the preset rolls a new variation
## from [member base] plus a random amount within [member ranges].

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
