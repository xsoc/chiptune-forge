class_name ChipVorbis
extends RefCounted
## A small Ogg Vorbis encoder written in GDScript, so songs and sounds can be
## exported as OGG files and pre-rendered to an [AudioStreamOggVorbis]
## without a native library.
##
## It is deliberately simple: every block is a long block (2048 samples),
## the floor is a fixed set of 32 posts shared by both channels, stereo is
## square-polar coupled, and the residue uses six cascades over eight
## lattice codebooks whose Huffman codes are fitted to the audio in a quick
## first pass. Loop points go in the comment header as LOOPSTART and
## LOOPLENGTH, which many engines and players read.
##
## Use [method from_wav] or [method from_frames], then call [method step]
## until it returns true (or [method run]), then read [member bytes].

const BLOCK := 2048
const HALF := 1024
const VENDOR := "Chiptune Forge Vorbis encoder"
## Floor values index this table (the Vorbis floor 1 inverse dB table:
## 256 steps of about 0.55 dB, from 1.0649863e-07 up to 1.0).
const DB_BASE := 1.0649863e-07
const DB_RATIO := 1.0649863
const FLOOR_MULTIPLIER := 2
const FLOOR_RANGE := 128
## The floor posts between 0 and 1024, sorted. The header lists them coarse
## to fine so each one is predicted from its neighbours.
const POSTS := [4, 8, 12, 16, 20, 24, 30, 36, 44, 52, 62, 72, 84, 98, 114, 132, 152, 176, 204, 236, 272, 314, 362, 418, 482, 556, 640, 736, 848, 960]
## The floor never goes below this (in table steps; about -90 dB from full
## scale), nor more than [constant RANGE] steps (about 66 dB) under the
## block's loudest band, nor less than [constant SPREAD] steps per post
## under a louder neighbour's.
const QUIET := 90.0
const RANGE := 120.0
const SPREAD := 24.0
const PARTITION := 32
## Residue values are clamped to this many floor steps.
const LIMIT := 787
const BOOK_Y := 0
const BOOK_CLASS := 1
const BOOK_PM1 := 2
const BOOK_PM2 := 3
const BOOK_S5 := 4
const BOOK_S5X4 := 5
const BOOK_S25 := 6
const BOOK_S5X2 := 7
## Per book: dimensions, entries, and for lattice books [minimum, step,
## values per dimension, bits per value].
const BOOKS := [
	[1, 128, []],
	[1, 6, []],
	[4, 81, [-1, 1, 3, 2]],
	[4, 625, [-2, 1, 5, 3]],
	[4, 81, [-5, 5, 3, 2]],
	[2, 81, [-20, 5, 9, 4]],
	[1, 63, [-775, 25, 63, 6]],
	[4, 625, [-10, 5, 5, 3]],
]
## Per residue class, the book for each pass. Class 0 is silence; the
## others cover peaks of 1, 2, 7, 22 and [constant LIMIT] floor steps.
const CASCADES := [[], [BOOK_PM1], [BOOK_PM2], [BOOK_S5, BOOK_PM2], [BOOK_S5X4, BOOK_PM2], [BOOK_S25, BOOK_S5X2, BOOK_PM2]]
## Blocks looked at to fit the Huffman codes.
const SCAN_BLOCKS := 256

## The finished Ogg file, once [member done].
var bytes := PackedByteArray()
var done := false
var channels := 2
var rate := 44100
## Frames in the source.
var length := 0
## Peak residue in floor steps: higher means finer quantisation and bigger
## files.
var precision := 8.0

var _source: Variant
var _source_offset := 0
var _comments := PackedStringArray()
var _block := 0
var _last_block := 0
var _page_seq := 0
var _serial := 0x43464f52
var _page_packets: Array[PackedByteArray] = []
var _page_granule := 0
var _scan: PackedInt32Array
var _scanned := 0
var _counts: Array[PackedFloat64Array] = []
var _lengths: Array[PackedInt32Array] = []
var _codes: Array[PackedInt64Array] = []

static var _tables_ready := false
static var _window := PackedFloat64Array()
static var _pre_cos := PackedFloat64Array()
static var _pre_sin := PackedFloat64Array()
static var _post_cos := PackedFloat64Array()
static var _post_sin := PackedFloat64Array()
static var _fft_cos := PackedFloat64Array()
static var _fft_sin := PackedFloat64Array()
static var _bitrev := PackedInt32Array()
static var _crc_table := PackedInt64Array()
static var _floor_db := PackedFloat64Array()
## Floor X values in header order: 0, 1024, then the posts coarse to fine.
static var _floor_x := PackedInt32Array()
static var _low_n := PackedInt32Array()
static var _high_n := PackedInt32Array()
## Header indexes sorted by X.
static var _sorted := PackedInt32Array()
## [lo, hi) bins each header post measures the spectrum over.
static var _region_lo := PackedInt32Array()
static var _region_hi := PackedInt32Array()


## An encoder for 16-bit PCM WAV bytes, such as the app's own WAV exports.
## Loop points come from the smpl chunk. Returns null if the WAV is not
## 16-bit PCM.
static func from_wav(wav: PackedByteArray, comments := PackedStringArray()) -> ChipVorbis:
	var info := parse_wav(wav)
	if info.is_empty():
		return null
	var encoder := ChipVorbis.new()
	encoder.channels = info.channels
	encoder.rate = info.rate
	encoder.length = info.frames
	encoder._source = wav
	encoder._source_offset = info.data
	encoder._begin(comments, info.loop_begin, info.loop_end)
	return encoder


## An encoder for stereo frames (-1 to 1), with an optional loop.
static func from_frames(frames: PackedVector2Array, mix_rate: int, loop_begin := -1, loop_end := -1, comments := PackedStringArray()) -> ChipVorbis:
	var encoder := ChipVorbis.new()
	encoder.channels = 2
	encoder.rate = mix_rate
	encoder.length = frames.size()
	encoder._source = frames
	encoder._begin(comments, loop_begin, loop_end)
	return encoder


## Reads the format, data and smpl chunks of a 16-bit PCM WAV. Returns {}
## for anything else.
static func parse_wav(wav: PackedByteArray) -> Dictionary:
	if wav.size() < 12 or wav.slice(0, 4).get_string_from_ascii() != "RIFF" or wav.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var info := {"loop_begin": -1, "loop_end": -1}
	var at := 12
	while at + 8 <= wav.size():
		var id := wav.slice(at, at + 4).get_string_from_ascii()
		var size := wav.decode_u32(at + 4)
		var body := at + 8
		match id:
			"fmt ":
				if wav.decode_u16(body) != 1 or wav.decode_u16(body + 14) != 16:
					return {}
				info.channels = wav.decode_u16(body + 2)
				info.rate = wav.decode_u32(body + 4)
			"data":
				info.data = body
				info.frames = mini(size, wav.size() - body) / (2 * int(info.get("channels", 1)))
			"smpl":
				if size >= 60 and wav.decode_u32(body + 28) > 0:
					info.loop_begin = wav.decode_u32(body + 44)
					info.loop_end = wav.decode_u32(body + 48) + 1
		at = body + size + (size & 1)
	if not info.has("channels") or not info.has("data") or info.channels < 1 or info.channels > 2:
		return {}
	return info


## Encodes up to [param blocks] blocks. Returns true when the file is done.
func step(blocks := 32) -> bool:
	if _scanned < _scan.size():
		var counter := _Bits.new()
		counter.counting = true
		var scan_end := mini(_scanned + blocks, _scan.size())
		while _scanned < scan_end:
			_encode_block(_scan[_scanned], counter)
			_scanned += 1
		if _scanned == _scan.size():
			_fit_books()
			_write_page([_identification()], 0, 0x02)
			_write_page([_comment_header(), _setup_header()], 0, 0)
		return false
	var end := mini(_block + blocks, _last_block + 1)
	while _block < end:
		var w := _Bits.new()
		_encode_block(_block, w)
		var last := _block == _last_block
		_add_packet(w.finish(), length if last else _block * HALF, last)
		_block += 1
	if _block > _last_block and not done:
		done = true
		_source = null
	return done


## Runs the encoder to the end and returns the file.
func run() -> PackedByteArray:
	while not step(256):
		pass
	return bytes


## How far through the encoding is, from 0 to 1.
func get_progress() -> float:
	return (_scanned + _block) / float(_scan.size() + _last_block + 1)


func _begin(comments: PackedStringArray, loop_begin: int, loop_end: int) -> void:
	_ensure_tables()
	_comments = comments.duplicate()
	if loop_begin >= 0 and loop_end > loop_begin:
		_comments.append("LOOPSTART=%d" % loop_begin)
		_comments.append("LOOPLENGTH=%d" % (loop_end - loop_begin))
	_last_block = maxi(1, ceili(length / float(HALF)))
	var every := maxi(1, ceili((_last_block + 1) / float(SCAN_BLOCKS)))
	for b in range(0, _last_block + 1, every):
		_scan.append(b)
	for book in BOOKS:
		var counts := PackedFloat64Array()
		counts.resize(book[1])
		_counts.append(counts)


## Huffman codes fitted to the entries the scan used.
func _fit_books() -> void:
	for counts in _counts:
		var total := 0.0
		for c in counts:
			total += c
		var weights := PackedFloat64Array()
		weights.resize(counts.size())
		for e in counts.size():
			weights[e] = counts[e] + 0.02
		var lengths := huffman_lengths(weights, (total + 1.0) * 2e-6)
		_lengths.append(lengths)
		_codes.append(codewords(lengths))


# --- Headers ---------------------------------------------------------------

func _identification() -> PackedByteArray:
	var w := _Bits.new()
	w.put(1, 8)
	w.put_text("vorbis")
	w.put(0, 32)
	w.put(channels, 8)
	w.put(rate, 32)
	w.put(0, 32)
	w.put(0, 32)
	w.put(0, 32)
	w.put(8, 4) # short blocks: 256 (never used)
	w.put(11, 4) # long blocks: 2048
	w.put(1, 1)
	return w.finish()


func _comment_header() -> PackedByteArray:
	var w := _Bits.new()
	w.put(3, 8)
	w.put_text("vorbis")
	var vendor := VENDOR.to_utf8_buffer()
	w.put(vendor.size(), 32)
	w.put_bytes(vendor)
	w.put(_comments.size(), 32)
	for comment in _comments:
		var text := comment.to_utf8_buffer()
		w.put(text.size(), 32)
		w.put_bytes(text)
	w.put(1, 1)
	return w.finish()


func _setup_header() -> PackedByteArray:
	var w := _Bits.new()
	w.put(5, 8)
	w.put_text("vorbis")
	# Codebooks.
	w.put(BOOKS.size() - 1, 8)
	for book in BOOKS.size():
		var info: Array = BOOKS[book]
		w.put(0x564342, 24)
		w.put(info[0], 16)
		w.put(info[1], 24)
		w.put(0, 1) # not ordered
		w.put(0, 1) # not sparse
		for length_bits in _lengths[book]:
			w.put(length_bits - 1, 5)
		var lattice: Array = info[2]
		if lattice.is_empty():
			w.put(0, 4)
		else:
			_put_lattice(w, lattice[0], lattice[1], lattice[2], lattice[3])
	# Time domain transforms: one placeholder.
	w.put(0, 6)
	w.put(0, 16)
	# Floors: one floor 1.
	w.put(0, 6)
	w.put(1, 16)
	w.put(POSTS.size(), 5)
	for i in POSTS.size():
		w.put(0, 4)
	w.put(0, 3) # class 0: one value per partition
	w.put(0, 2) # no subclasses
	w.put(BOOK_Y + 1, 8)
	w.put(FLOOR_MULTIPLIER - 1, 2)
	w.put(10, 4)
	for i in range(2, _floor_x.size()):
		w.put(_floor_x[i], 10)
	# Residues: one type 1.
	w.put(0, 6)
	w.put(1, 16)
	w.put(0, 24)
	w.put(HALF, 24)
	w.put(PARTITION - 1, 24)
	w.put(CASCADES.size() - 1, 6)
	w.put(BOOK_CLASS, 8)
	for cascade: Array in CASCADES:
		w.put((1 << cascade.size()) - 1, 3)
		w.put(0, 1)
	for cascade: Array in CASCADES:
		for book: int in cascade:
			w.put(book, 8)
	# Mappings: one; stereo is coupled, left as magnitude, right as angle.
	w.put(0, 6)
	w.put(0, 16)
	w.put(0, 1)
	if channels == 2:
		w.put(1, 1)
		w.put(0, 8)
		w.put(0, 1)
		w.put(1, 1)
	else:
		w.put(0, 1)
	w.put(0, 2)
	w.put(0, 8)
	w.put(0, 8)
	w.put(0, 8)
	# Modes: one, long blocks.
	w.put(0, 6)
	w.put(1, 1)
	w.put(0, 16)
	w.put(0, 16)
	w.put(0, 8)
	w.put(1, 1)
	return w.finish()


static func _put_lattice(w: _Bits, minimum: int, delta: int, values: int, value_bits: int) -> void:
	w.put(1, 4)
	w.put(_float32(minimum), 32)
	w.put(_float32(delta), 32)
	w.put(value_bits - 1, 4)
	w.put(0, 1)
	for i in values:
		w.put(i, value_bits)


## Vorbis's own float format, for whole numbers.
static func _float32(value: int) -> int:
	if value == 0:
		return 0
	return (0x80000000 if value < 0 else 0) | (788 << 21) | absi(value)


# --- Audio packets ---------------------------------------------------------

func _encode_block(index: int, w: _Bits) -> void:
	w.put(0, 1)
	w.put(1, 1) # previous window long
	w.put(1, 1) # next window long
	var spectra: Array[PackedFloat64Array] = []
	for ch in channels:
		spectra.append(_mdct(_samples(index, ch)))
	var floor_curve := _encode_floor(w, spectra)
	if floor_curve.is_empty():
		return
	var q: Array[PackedInt32Array] = []
	for ch in channels:
		var values := PackedInt32Array()
		values.resize(HALF)
		var coeffs := spectra[ch]
		for k in HALF:
			values[k] = clampi(roundi(coeffs[k] / floor_curve[k]), -LIMIT, LIMIT)
		q.append(values)
	if channels == 2:
		_couple(q[0], q[1])
	var parts: Array[PackedInt32Array] = []
	var passes: Array = []
	for ch in channels:
		var classes := PackedInt32Array()
		classes.resize(HALF / PARTITION)
		var layers: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		for layer in layers:
			layer.resize(HALF)
		for p in classes.size():
			var peak := 0
			for k in range(p * PARTITION, (p + 1) * PARTITION):
				peak = maxi(peak, absi(q[ch][k]))
			var part_class := 0 if peak == 0 else (1 if peak <= 1 else (2 if peak <= 2 else (3 if peak <= 7 else (4 if peak <= 22 else 5))))
			classes[p] = part_class
			for k in range(p * PARTITION, (p + 1) * PARTITION):
				var v := q[ch][k]
				match part_class:
					1, 2:
						layers[0][k] = v
					3, 4:
						var b := roundi(v / 5.0)
						layers[0][k] = 5 * b
						layers[1][k] = v - 5 * b
					5:
						var a := clampi(roundi(v / 25.0), -31, 31)
						var r := v - 25 * a
						var b := roundi(r / 5.0)
						layers[0][k] = 25 * a
						layers[1][k] = 5 * b
						layers[2][k] = r - 5 * b
		parts.append(classes)
		passes.append(layers)
	for pass_index in 3:
		for p in HALF / PARTITION:
			if pass_index == 0:
				for ch in channels:
					_put_entry(w, BOOK_CLASS, parts[ch][p])
			for ch in channels:
				var cascade: Array = CASCADES[parts[ch][p]]
				if pass_index < cascade.size():
					_put_vectors(w, cascade[pass_index], passes[ch][pass_index], p * PARTITION)


## Square-polar coupling, the inverse of the decoder's: exact on integers.
static func _couple(left: PackedInt32Array, right: PackedInt32Array) -> void:
	for k in left.size():
		var l := left[k]
		var r := right[k]
		if absi(l) > absi(r):
			left[k] = l
			right[k] = l - r if l > 0 else r - l
		else:
			left[k] = r
			right[k] = l - r if r > 0 else r - l


func _put_vectors(w: _Bits, book: int, values: PackedInt32Array, at: int) -> void:
	var info: Array = BOOKS[book]
	var dims: int = info[0]
	var lattice: Array = info[2]
	var minimum: int = lattice[0]
	var step_size: int = lattice[1]
	var per: int = lattice[2]
	for k in range(at, at + PARTITION, dims):
		var entry := 0
		var scale := 1
		for d in dims:
			entry += ((values[k + d] - minimum) / step_size) * scale
			scale *= per
		_put_entry(w, book, entry)


func _put_entry(w: _Bits, book: int, entry: int) -> void:
	if w.counting:
		_counts[book][entry] += 1.0
	else:
		w.put(_codes[book][entry], _lengths[book][entry])


## Chooses the floor, shared by every channel, writes it once per channel,
## and returns the curve the decoder will draw from it (one value per
## coefficient), or an empty array when the block is silent.
func _encode_floor(w: _Bits, spectra: Array[PackedFloat64Array]) -> PackedFloat64Array:
	var count := _floor_x.size()
	var log_ratio := log(DB_RATIO)
	# Each post's loudest coefficient, in floor table steps (about 0.55 dB).
	var peak := PackedFloat64Array()
	peak.resize(count)
	var loudest := -1000.0
	for s in count:
		var i := _sorted[s]
		var top := 0.0
		for coeffs in spectra:
			for k in range(_region_lo[i], _region_hi[i]):
				top = maxf(top, absf(coeffs[k]))
		peak[s] = log(top / DB_BASE) / log_ratio if top > 0.0 else -1000.0
		loudest = maxf(loudest, peak[s])
	var precision_steps := log(precision) / log_ratio
	var target := PackedInt32Array()
	target.resize(count)
	var loud := loudest - precision_steps > QUIET
	# The floor sits [member precision] below each band's peak, or under the
	# spread of a louder neighbour, or at the quiet limits, whichever is
	# highest: quantisation noise under it is masked or inaudible.
	for s in count:
		var level := maxf(QUIET, loudest - RANGE)
		for t in count:
			level = maxf(level, peak[t] - precision_steps - SPREAD * absi(s - t))
		target[_sorted[s]] = clampi(roundi(level / FLOOR_MULTIPLIER), 0, FLOOR_RANGE - 1)
	if not loud:
		for ch in channels:
			w.put(0, 1)
		return PackedFloat64Array()
	var final_y := PackedInt32Array()
	final_y.resize(count)
	var used := PackedByteArray()
	used.resize(count)
	var vals := PackedInt32Array()
	vals.resize(count)
	final_y[0] = target[0]
	final_y[1] = target[1]
	used[0] = 1
	used[1] = 1
	for i in range(2, count):
		var lo := _low_n[i]
		var hi := _high_n[i]
		var predicted := _render_point(_floor_x[lo], final_y[lo], _floor_x[hi], final_y[hi], _floor_x[i])
		var room := mini(FLOOR_RANGE - predicted, predicted)
		var d := target[i] - predicted
		var val := 0
		if absi(d) > 1:
			if d > 0:
				val = 2 * d if d < room else target[i]
			else:
				val = -2 * d - 1 if -d <= room else FLOOR_RANGE - 1 - target[i]
		vals[i] = val
		if val == 0:
			final_y[i] = predicted
		else:
			final_y[i] = target[i]
			used[lo] = 1
			used[hi] = 1
			used[i] = 1
	for ch in channels:
		w.put(1, 1)
		w.put(target[0], 7)
		w.put(target[1], 7)
		for i in range(2, count):
			_put_entry(w, BOOK_Y, vals[i])
	# Draw the curve exactly as the decoder does.
	var curve := PackedFloat64Array()
	curve.resize(HALF)
	var lx := 0
	var ly := final_y[_sorted[0]] * FLOOR_MULTIPLIER
	for s in range(1, count):
		var i := _sorted[s]
		if used[i]:
			var hy := final_y[i] * FLOOR_MULTIPLIER
			var hx := _floor_x[i]
			_render_line(lx, ly, hx, hy, curve)
			lx = hx
			ly = hy
	return curve


static func _render_point(x0: int, y0: int, x1: int, y1: int, x: int) -> int:
	var dy := y1 - y0
	var adx := x1 - x0
	var off := (absi(dy) * (x - x0)) / adx
	return y0 - off if dy < 0 else y0 + off


static func _render_line(x0: int, y0: int, x1: int, y1: int, curve: PackedFloat64Array) -> void:
	var dy := y1 - y0
	var adx := x1 - x0
	var base := dy / adx
	var sy := base - 1 if dy < 0 else base + 1
	var ady := absi(dy) - absi(base) * adx
	var y := y0
	var err := 0
	if x0 < HALF:
		curve[x0] = _floor_db[y]
	for x in range(x0 + 1, mini(x1, HALF)):
		err += ady
		if err >= adx:
			err -= adx
			y += sy
		else:
			y += base
		curve[x] = _floor_db[y]


## The windowed block of one channel: 2048 samples centred on
## index * 1024, zero outside the source.
func _samples(index: int, ch: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(BLOCK)
	var start := (index - 1) * HALF
	var from := maxi(0, -start)
	var to := mini(BLOCK, length - start)
	if _source is PackedByteArray:
		var wav: PackedByteArray = _source
		var stride := channels * 2
		var at := _source_offset + (start + from) * stride + ch * 2
		for i in range(from, to):
			out[i] = wav.decode_s16(at) / 32768.0 * _window[i]
			at += stride
	else:
		var frames: PackedVector2Array = _source
		for i in range(from, to):
			var frame := frames[start + i]
			out[i] = (frame.x if ch == 0 else frame.y) * _window[i]
	return out


## The MDCT of a windowed block, scaled the way the decoder expects: a fold
## to a DCT-IV, done with a 512-point complex FFT.
static func _mdct(x: PackedFloat64Array) -> PackedFloat64Array:
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(512)
	im.resize(512)
	for j in 512:
		var n := 2 * j
		var m := HALF - 1 - 2 * j
		var a := (-x[1535 - n] - x[1536 + n]) if n < 512 else (x[n - 512] - x[1023 - (n - 512)])
		var b := (-x[1535 - m] - x[1536 + m]) if m < 512 else (x[m - 512] - x[1023 - (m - 512)])
		var c := _pre_cos[j]
		var s := _pre_sin[j]
		var r := _bitrev[j]
		re[r] = a * c - b * s
		im[r] = a * s + b * c
	var size := 2
	while size <= 512:
		var half := size >> 1
		var stride := 512 / size
		for start in range(0, 512, size):
			for k in half:
				var c := _fft_cos[k * stride]
				var s := _fft_sin[k * stride]
				var p := start + k
				var q := p + half
				var tr := re[q] * c - im[q] * s
				var ti := re[q] * s + im[q] * c
				re[q] = re[p] - tr
				im[q] = im[p] - ti
				re[p] += tr
				im[p] += ti
		size <<= 1
	var out := PackedFloat64Array()
	out.resize(HALF)
	for j in 512:
		var c := _post_cos[j]
		var s := _post_sin[j]
		out[2 * j] = re[j] * c - im[j] * s
		out[HALF - 1 - 2 * j] = -(re[j] * s + im[j] * c)
	return out


# --- Ogg pages -------------------------------------------------------------

func _add_packet(packet: PackedByteArray, granule: int, last: bool) -> void:
	var segments := 0
	for p in _page_packets:
		segments += p.size() / 255 + 1
	var size := 0
	for p in _page_packets:
		size += p.size()
	if not _page_packets.is_empty() and (segments + packet.size() / 255 + 1 > 255 or size + packet.size() > 4096):
		_write_page(_page_packets, _page_granule, 0)
		_page_packets = []
	_page_packets.append(packet)
	_page_granule = granule
	# The first packet (which makes no sound) gets a page to itself, so the
	# last page is never also the first and decoders trim its end.
	if granule == 0 and not last:
		_write_page(_page_packets, 0, 0)
		_page_packets = []
	elif last:
		_write_page(_page_packets, _page_granule, 0x04)
		_page_packets = []


func _write_page(packets: Array, granule: int, flags: int) -> void:
	var lacing := PackedByteArray()
	var body := PackedByteArray()
	for packet: PackedByteArray in packets:
		var left := packet.size()
		while left >= 255:
			lacing.append(255)
			left -= 255
		lacing.append(left)
		body.append_array(packet)
	var page := PackedByteArray()
	page.append_array("OggS".to_ascii_buffer())
	page.append(0)
	page.append(flags)
	page.resize(27)
	page.encode_s64(6, granule)
	page.encode_u32(14, _serial)
	page.encode_u32(18, _page_seq)
	page.encode_u32(22, 0)
	page[26] = lacing.size()
	page.append_array(lacing)
	page.append_array(body)
	page.encode_u32(22, _crc(page))
	bytes.append_array(page)
	_page_seq += 1


static func _crc(data: PackedByteArray) -> int:
	var crc := 0
	for b in data:
		crc = ((crc << 8) & 0xffffffff) ^ _crc_table[((crc >> 24) ^ b) & 0xff]
	return crc


# --- Tables ----------------------------------------------------------------

static func _ensure_tables() -> void:
	if _tables_ready:
		return
	_window.resize(BLOCK)
	for i in BLOCK:
		var s := sin((i + 0.5) / BLOCK * PI)
		_window[i] = sin(PI / 2.0 * s * s)
	for table in [_pre_cos, _pre_sin, _post_cos, _post_sin, _fft_cos, _fft_sin]:
		table.resize(512)
	_bitrev.resize(512)
	for j in 512:
		var a := -PI * (j + 0.25) / HALF
		_pre_cos[j] = cos(a)
		_pre_sin[j] = sin(a)
		# The decoder's inverse MDCT is unscaled; 2/1024 makes the round trip unity.
		var b := -PI * j / HALF
		_post_cos[j] = cos(b) * 2.0 / HALF
		_post_sin[j] = sin(b) * 2.0 / HALF
		var f := -TAU * j / 512.0
		_fft_cos[j] = cos(f)
		_fft_sin[j] = sin(f)
		var r := 0
		for bit in 9:
			if j & (1 << bit):
				r |= 1 << (8 - bit)
		_bitrev[j] = r
	_crc_table.resize(256)
	for i in 256:
		var r := i << 24
		for bit in 8:
			r = ((r << 1) ^ 0x04c11db7) if r & 0x80000000 else (r << 1)
			r &= 0xffffffff
		_crc_table[i] = r
	_floor_db.resize(256)
	for i in 256:
		_floor_db[i] = DB_BASE * pow(DB_RATIO, i)
	_build_floor()
	_tables_ready = true


static func _build_floor() -> void:
	var order: Array = []
	var ranges: Array = [[0, POSTS.size()]]
	while not ranges.is_empty():
		var r: Array = ranges.pop_front()
		if r[0] >= r[1]:
			continue
		var mid: int = (r[0] + r[1]) / 2
		order.append(POSTS[mid])
		ranges.append([r[0], mid])
		ranges.append([mid + 1, r[1]])
	_floor_x = PackedInt32Array([0, HALF] + order)
	var count := _floor_x.size()
	_low_n.resize(count)
	_high_n.resize(count)
	for i in range(2, count):
		var lo := 0
		var hi := 1
		for j in i:
			if _floor_x[j] < _floor_x[i] and _floor_x[j] > _floor_x[lo]:
				lo = j
			if _floor_x[j] > _floor_x[i] and _floor_x[j] < _floor_x[hi]:
				hi = j
		_low_n[i] = lo
		_high_n[i] = hi
	var by_x: Array = range(count)
	by_x.sort_custom(func(a: int, b: int) -> bool: return _floor_x[a] < _floor_x[b])
	_sorted = PackedInt32Array(by_x)
	_region_lo.resize(count)
	_region_hi.resize(count)
	for s in count:
		var i: int = by_x[s]
		var x := _floor_x[i]
		var left := 0 if s == 0 else (_floor_x[by_x[s - 1]] + x) / 2
		var right := HALF if s == count - 1 else (_floor_x[by_x[s + 1]] + x + 1) / 2
		_region_lo[i] = left
		_region_hi[i] = maxi(right, left + 1)


## Huffman code lengths, every weight raised to at least [param minimum] so
## no code grows past 32 bits.
static func huffman_lengths(weights: PackedFloat64Array, minimum := 0.0) -> PackedInt32Array:
	var count := weights.size()
	var order: Array = range(count)
	order.sort_custom(func(a: int, b: int) -> bool: return weights[a] < weights[b])
	# Two queues: the sorted leaves, and merged nodes (made in rising order).
	var weight := PackedFloat64Array()
	weight.resize(2 * count)
	var parent := PackedInt32Array()
	parent.resize(2 * count)
	for i in count:
		weight[i] = maxf(weights[order[i]], minimum)
	var leaf := 0
	var node := count
	var made := count
	while made < 2 * count - 1:
		var pick := PackedInt32Array()
		for n in 2:
			if leaf < count and (node >= made or weight[leaf] <= weight[node]):
				pick.append(leaf)
				leaf += 1
			else:
				pick.append(node)
				node += 1
		weight[made] = weight[pick[0]] + weight[pick[1]]
		parent[pick[0]] = made
		parent[pick[1]] = made
		made += 1
	var depth := PackedInt32Array()
	depth.resize(2 * count)
	for n in range(2 * count - 3, -1, -1):
		depth[n] = depth[parent[n]] + 1
	var lengths := PackedInt32Array()
	lengths.resize(count)
	for i in count:
		lengths[order[i]] = maxi(depth[i], 1)
	return lengths


## Codewords for these lengths, assigned in entry order as the Vorbis
## decoder does, bit-reversed so they can be written least significant bit
## first.
static func codewords(lengths: PackedInt32Array) -> PackedInt64Array:
	var marker := PackedInt64Array()
	marker.resize(33)
	var out := PackedInt64Array()
	out.resize(lengths.size())
	for i in lengths.size():
		var length_bits := lengths[i]
		var entry := marker[length_bits]
		out[i] = entry
		for j in range(length_bits, 0, -1):
			if marker[j] & 1:
				if j == 1:
					marker[1] += 1
				else:
					marker[j] = marker[j - 1] << 1
				break
			marker[j] += 1
		for j in range(length_bits + 1, 33):
			if (marker[j] >> 1) == entry:
				entry = marker[j]
				marker[j] = marker[j - 1] << 1
			else:
				break
	for i in out.size():
		var reversed := 0
		for bit in lengths[i]:
			if out[i] & (1 << bit):
				reversed |= 1 << (lengths[i] - 1 - bit)
		out[i] = reversed
	return out


## Packs bits least significant first, as Vorbis and Ogg do.
class _Bits:
	var data := PackedByteArray()
	## A writer that only counts codebook entries, for fitting the codes.
	var counting := false
	var _acc := 0
	var _count := 0

	func put(value: int, bits: int) -> void:
		_acc |= (value & ((1 << bits) - 1)) << _count
		_count += bits
		while _count >= 8:
			data.append(_acc & 0xff)
			_acc >>= 8
			_count -= 8

	func put_text(text: String) -> void:
		put_bytes(text.to_ascii_buffer())

	func put_bytes(source: PackedByteArray) -> void:
		for b in source:
			put(b, 8)

	func finish() -> PackedByteArray:
		if _count > 0:
			data.append(_acc & 0xff)
			_acc = 0
			_count = 0
		return data
