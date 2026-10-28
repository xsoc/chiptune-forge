@tool
class_name ChipProfile
extends Resource
## A sound chip target: its voices, limits and export format.

@export var id := ""
@export var display_name := ""
## Short hardware name, such as "Ricoh 2A03".
@export var chip_name := ""
@export_multiline var description := ""
## Release phase from the project plan. Phase 1 targets are available now.
@export var phase := 1
@export var available := false
## One entry per hardware voice: {"name": "Pulse 1", "waves": ["pulse"]}.
@export var voices: Array[Dictionary] = []
@export var stereo := true
@export var echo := true
## Most notes the chip can play at once, or 0 for no limit.
@export var max_voices := 0
@export var export_formats: PackedStringArray = []
