class_name RegStream
extends RefCounted
## The register stream our own console players read (the Z80 player for the
## AY-3-8910 and the 6502 player for the SID): each frame sets the registers
## that changed, and stretches that repeat earlier ones play them again with
## a call command.
##
## Commands: a register number (0 to 127) and its value; 128 to 191 end the
## frame and wait 0 to 63 more frames; 192 o, l plays the l bytes at offset
## o (from the start of the data) then goes on; 254 jumps to the loop; 255
## ends. The first frame and the loop frame set every register.

const WAIT := 0x80
const CALL := 0xC0
const LOOP := 0xFE
const END := 0xFF
const MAX_WAIT := 63


## Encodes recorded frames as a stream that will sit at [param base] in the
## data. Returns {bytes, loop_at: where the loop frame starts, from the
## start of the data}.
static func encode(frames: Array, loop_frame: int, base: int, registers: PackedInt32Array) -> Dictionary:
	# One token per frame that writes registers (or starts the loop), with
	# the empty frames after it folded into its wait.
	var tokens: Array[PackedByteArray] = []
	var token_frame := PackedInt32Array()
	var prev := PackedInt32Array()
	for f in frames.size():
		var regs: PackedInt32Array = frames[f]
		var bytes := PackedByteArray()
		for r in registers:
			if f == 0 or f == loop_frame or regs[r] != prev[r]:
				bytes.append(r)
				bytes.append(regs[r] & 0xFF)
		prev = regs
		var last := tokens.size() - 1
		if bytes.is_empty() and f != loop_frame and last >= 0:
			var t := tokens[last]
			var wait := t[t.size() - 1] & 0x3F
			if wait < MAX_WAIT:
				t[t.size() - 1] = WAIT | (wait + 1)
				tokens[last] = t
				continue
		bytes.append(WAIT)
		tokens.append(bytes)
		token_frame.append(f)
	var loop_token := token_frame.find(loop_frame) if loop_frame >= 0 else -1
	# Repeats of earlier stretches become calls. A call may only point at
	# tokens written out as they are, one after another, and never runs
	# across the loop point.
	var out := PackedByteArray()
	var literal_at := PackedInt32Array()
	literal_at.resize(tokens.size())
	literal_at.fill(-1)
	var seen := {}
	var loop_at := -1
	var i := 0
	while i < tokens.size():
		if i == loop_token:
			loop_at = base + out.size()
		var key := tokens[i].hex_encode()
		var best_len := 0
		var best_bytes := 0
		var best_from := -1
		var candidates: Array = seen.get(key, [])
		for k in range(candidates.size() - 1, maxi(candidates.size() - 64, 0) - 1, -1):
			var j: int = candidates[k]
			var n := 0
			var bytes := 0
			while i + n < tokens.size() and j + n < i:
				if n > 0 and i + n == loop_token:
					break
				if literal_at[j + n] < 0 or tokens[j + n] != tokens[i + n]:
					break
				if n > 0 and literal_at[j + n] != literal_at[j + n - 1] + tokens[j + n - 1].size():
					break
				bytes += tokens[i + n].size()
				n += 1
			if bytes > best_bytes:
				best_bytes = bytes
				best_len = n
				best_from = j
		if best_bytes > 6:
			var at := base + literal_at[best_from]
			out.append_array([CALL, at & 0xFF, at >> 8, best_bytes & 0xFF, best_bytes >> 8])
			i += best_len
			continue
		literal_at[i] = out.size()
		out.append_array(tokens[i])
		if not seen.has(key):
			seen[key] = []
		seen[key].append(i)
		i += 1
	return {"bytes": out, "loop_at": loop_at}


## A stream as our players read it.
class Reader:
	extends RefCounted

	var data: PackedByteArray
	var pos := 0
	var wait := 0
	var ret := -1
	var end := 0
	var loop := 0
	var on := true
	var regs := PackedInt32Array()

	func _init(bytes: PackedByteArray, start: int, loop_at: int, reg_count: int, initial := {}) -> void:
		data = bytes
		pos = start
		loop = loop_at
		regs.resize(reg_count)
		for r in initial:
			regs[r] = initial[r]

	func step() -> void:
		if not on:
			return
		if wait > 0:
			wait -= 1
			return
		while true:
			if ret >= 0 and pos == end:
				pos = ret
				ret = -1
			var b := data[pos]
			pos += 1
			if b < 0x80:
				regs[b] = data[pos]
				pos += 1
			elif b < CALL:
				wait = b & 0x3F
				return
			elif b == CALL:
				var at := data.decode_u16(pos)
				var length := data.decode_u16(pos + 2)
				ret = pos + 4
				pos = at
				end = at + length
			elif b == LOOP:
				pos = loop
			else:
				on = false
				return
