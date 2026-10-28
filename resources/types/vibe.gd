@tool
class_name Vibe
extends Resource
## A mood preset. A vibe sets the scale, tempo feel, harmony and timbre of a
## song. Up to three vibes can be blended.

@export var id := ""
@export var display_name := ""
@export var group := ""
## One-line hint shown on the chip's tooltip.
@export_multiline var description := ""
@export_group("Harmony")
## Relative weight of each mode, for example {"major": 3, "lydian": 1}.
@export var mode_weights: Dictionary = {"major": 1.0}
## Relative weight of each progression family. See [code]ProgressionBook[/code].
@export var progression_weights: Dictionary = {}
## Chance of sevenths, sixths and ninths, 0 to 1.
@export_range(0.0, 1.0) var chord_colour := 0.2
## How many bars each chord lasts, on average.
@export_range(0.5, 4.0, 0.5) var bars_per_chord := 1.0
@export_group("Feel")
@export_range(40, 240) var tempo_min := 90
@export_range(40, 240) var tempo_max := 140
## 0 is calm and sparse, 1 is dense and driving.
@export_range(0.0, 1.0) var energy := 0.5
## 0 is dark and low, 1 is bright and high.
@export_range(0.0, 1.0) var brightness := 0.5
## Dissonance and chromatic movement, 0 to 1.
@export_range(0.0, 1.0) var tension := 0.2
## Detune, wobble and odd choices, 0 to 1.
@export_range(0.0, 1.0) var weirdness := 0.0
## Melody direction: -1 falls, 1 rises.
@export_range(-1.0, 1.0) var contour := 0.0
## Long, connected notes (1) against short, detached ones (0).
@export_range(0.0, 1.0) var legato := 0.5
@export_range(0.0, 1.0) var swing := 0.0
@export_range(0.0, 1.0) var echo := 0.2
@export_group("Form")
## Beats per bar override, or 0 to follow the style.
@export_range(0, 7) var beats_per_bar := 0
## Suggested form, or "" to follow the style. "jingle" makes a short stinger.
@export var form_hint := ""
## Suggested length in seconds, or 0 for the user's choice.
@export var length_hint := 0.0
