class_name WaveformView
extends Control
## Draws a sound's waveform as min and max bars.

@export var colour := Color("52d1c0")

var _peaks := PackedVector2Array()
var _seconds := 0.0


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, 90)


func set_samples(samples: PackedFloat32Array, mix_rate: int) -> void:
	_seconds = samples.size() / float(mix_rate)
	_peaks.clear()
	var buckets := 240
	var per := maxi(samples.size() / buckets, 1)
	for b in buckets:
		var lo := 0.0
		var hi := 0.0
		for i in range(b * per, mini((b + 1) * per, samples.size())):
			lo = minf(lo, samples[i])
			hi = maxf(hi, samples[i])
		_peaks.append(Vector2(lo, hi))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101116"))
	var mid := size.y / 2.0
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.08))
	if _peaks.is_empty():
		return
	var w := size.x / _peaks.size()
	for i in _peaks.size():
		var p := _peaks[i]
		draw_rect(Rect2(i * w, mid - p.y * mid, maxf(w - 1.0, 1.0), maxf((p.y - p.x) * mid, 1.0)), colour)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, size.y - 8), "%.2f s" % _seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9a9daa"))
