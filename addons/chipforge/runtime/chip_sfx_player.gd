@icon("res://addons/chipforge/icons/chip_sfx_player.svg")
class_name ChipSfxPlayer
extends Node
## Plays sound effects from a [ChipSfxKit], several at once.
##
## [codeblock]
## $Sfx.play("jump")
## [/codeblock]
## Sounds render once, the first time they play, and are cached after that.
## Call [method warm_up] during a loading screen to render them in advance.

@export var kit: ChipSfxKit
## How many sounds can overlap. The oldest one is cut when all are busy.
@export_range(1, 32) var polyphony := 4
@export_range(-60.0, 12.0, 0.1, "suffix:dB") var volume_db := 0.0
@export var bus: StringName = &"Master"

var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in polyphony:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		player.volume_db = volume_db
		add_child(player, false, Node.INTERNAL_MODE_FRONT)
		_voices.append(player)


## Plays the kit sound with [param id]. [param pitch_scale] above 1 is higher.
func play(id: String, pitch_scale := 1.0) -> void:
	if kit == null or not kit.sounds.has(id):
		push_warning("ChipSfxPlayer: no sound \"%s\" in the kit." % id)
		return
	play_sfx(kit.sounds[id], pitch_scale)


## Plays any [ChipSfx], whether or not it is in the kit.
func play_sfx(sfx: ChipSfx, pitch_scale := 1.0) -> void:
	if _voices.is_empty():
		return
	var player := _free_voice()
	player.stream = sfx.get_stream()
	player.pitch_scale = pitch_scale
	player.play()


func stop_all() -> void:
	for player in _voices:
		player.stop()


## Renders every sound in the kit now, so the first play has no delay.
func warm_up() -> void:
	if kit:
		for id in kit.sounds:
			kit.sounds[id].get_stream()


func _free_voice() -> AudioStreamPlayer:
	for player in _voices:
		if not player.playing:
			return player
	var player := _voices[_next]
	_next = (_next + 1) % _voices.size()
	return player
