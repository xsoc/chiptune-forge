class_name Pcg32
extends RefCounted
## PCG32 random number generator (pcg-random.org, Apache 2.0 / MIT).
##
## The generator never touches Godot's global random state, so a seed always
## gives the same numbers on every platform. Each generation stage gets its
## own stream from [method for_stream], which is what lets one stage be
## regenerated without changing the others.

const MULTIPLIER := 6364136223846793005
const MASK32 := 0xFFFFFFFF

var _state := 0
var _inc := 0


func _init(init_state := 0, init_seq := 0) -> void:
	seed_with(init_state, init_seq)


## Returns a generator for a named stream of a seed, for example
## [code]for_stream(seed, "melody")[/code].
static func for_stream(seed_value: int, stream_name: String) -> Pcg32:
	return Pcg32.new(seed_value & MASK32, hash_text(stream_name))


## Turns seed text into a 32-bit seed. Whole numbers are used as they are;
## anything else is hashed, so "dragon" is a valid seed.
static func seed_from_text(text: String) -> int:
	var trimmed := text.strip_edges()
	if trimmed.is_valid_int():
		return int(trimmed) & MASK32
	return hash_text(trimmed)


## 32-bit FNV-1a hash of UTF-8 text. Stable across Godot versions, unlike
## [method String.hash].
static func hash_text(text: String) -> int:
	var h := 0x811C9DC5
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * 0x01000193) & MASK32
	return h


func seed_with(init_state: int, init_seq: int) -> void:
	_state = 0
	_inc = (init_seq << 1) | 1
	next_u32()
	_state += init_state
	next_u32()


## Next 32-bit unsigned value.
func next_u32() -> int:
	var old := _state
	_state = old * MULTIPLIER + _inc
	# GDScript ints are signed, so mask after each right shift to make it
	# a logical shift.
	var xorshifted := ((((old >> 18) & 0x3FFFFFFFFFFF) ^ old) >> 27) & MASK32
	var rot := (old >> 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & MASK32


## Float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Integer in [lo, hi], both inclusive, without modulo bias.
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	var span := hi - lo + 1
	var limit := 4294967296 - (4294967296 % span)
	var value := next_u32()
	while value >= limit:
		value = next_u32()
	return lo + value % span


func range_float(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


func chance(probability: float) -> bool:
	return next_float() < probability


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_int(0, items.size() - 1)]


## Picks a key from a dictionary of key to weight. Keys are visited in sorted
## order so the result does not depend on how the dictionary was built.
func pick_weighted(weights: Dictionary) -> Variant:
	var keys := weights.keys()
	keys.sort()
	var total := 0.0
	for key in keys:
		total += maxf(float(weights[key]), 0.0)
	if total <= 0.0:
		return keys[0] if not keys.is_empty() else null
	var roll := next_float() * total
	for key in keys:
		roll -= maxf(float(weights[key]), 0.0)
		if roll < 0.0:
			return key
	return keys[keys.size() - 1]


## Picks an index using an array of weights.
func pick_index_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return 0
	var roll := next_float() * total
	for i in weights.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll < 0.0:
			return i
	return weights.size() - 1


func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := range_int(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
