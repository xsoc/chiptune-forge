class_name SnesBrr
extends RefCounted
## BRR, the SNES's 4-bit sample compression: blocks of 9 bytes, each a header
## (range, filter, loop and end flags) and 16 four-bit samples.
##
## [method encode] is a port of the encoder in PVSnesLib's smconv (brr.cpp,
## MIT), the tool that turns our Impulse Tracker modules into a soundbank,
## so the samples the preview plays are the ones the console will play.
## [method decode] does what the S-DSP does when it plays them.

const BLOCK_BYTES := 9
const FLAG_END := 1
const FLAG_LOOP := 2
## smconv's limit on the error at the loop start before it redoes the loop
## with filter 0.
const LOOP_LOSS_TOLERANCE := 30000


## Encodes 16-bit samples ([param pcm], -32768 to 32767) as BRR. The loop
## ([param loop_start], [param loop_length] samples, or no loop when the
## length is 0) must already be a multiple of 16 samples long and start on
## a multiple of 16, as smconv requires; a sample without a loop is padded
## with silence to a whole block. Returns {data: PackedByteArray, loop:
## byte offset of the loop block}.
static func encode(pcm: PackedInt32Array, loop_start := 0, loop_length := 0) -> Dictionary:
	var data := pcm.duplicate()
	var length := data.size()
	if loop_length > 0:
		length = mini(length, loop_start + loop_length)
		data.resize(length)
		assert(loop_length % 16 == 0 and loop_start % 16 == 0, "loops must be whole BRR blocks")
	elif length % 16 != 0:
		var pad := 16 - length % 16
		for i in pad:
			data.append(0)
		length += pad
	var out := PackedByteArray()
	out.resize(length / 16 * BLOCK_BYTES)
	var amp := 1.0
	# smconv lowers the level 1% at a time until no block overflows.
	while _generate(data, out, length, loop_start, loop_length, amp):
		amp -= 0.01
	return {"data": out, "loop": loop_start / 16 * BLOCK_BYTES}


## smconv's GenerateBRR. Returns true when a block overflowed and the whole
## sample must be redone quieter.
static func _generate(cdata: PackedInt32Array, output: PackedByteArray, srclength: int, srcloop: int, srclooplen: int, amp: float) -> bool:
	if srclength == 0:
		return false
	var sbuffer := PackedInt32Array()
	sbuffer.resize(18)
	var w_loop := 0
	var loop_v1 := 0
	var use_filter0 := false
	var redo := true
	var a := 0
	var w := 0
	var result := {}
	while redo:
		redo = false
		while a < srclength:
			for b in 16:
				if a + b >= srclength:
					sbuffer[b + 2] = 0
				else:
					sbuffer[b + 2] = clampi(int(floor(cdata[a + b] * amp + 0.5)), -32768, 32767)
			# Filter 0 on the first block (and on a redone loop start).
			result = _compress_block(sbuffer, 0 if a == 0 or use_filter0 else 4)
			use_filter0 = false
			if a == srcloop:
				w_loop = w
				loop_v1 = result["samp"][0]
			if result["overflow"]:
				return true
			sbuffer[1] = result["samp"][15]
			sbuffer[0] = result["samp"][14]
			output[w] = (int(result["range"]) << 4) + (int(result["filter"]) << 2)
			var nibbles: PackedInt32Array = result["data"]
			for b in 8:
				output[w + 1 + b] = nibbles[b * 2] * 16 + nibbles[b * 2 + 1]
			if srclooplen > 0:
				output[w] |= FLAG_LOOP
			w += BLOCK_BYTES
			a += 16
		w -= BLOCK_BYTES
		output[w] |= FLAG_END
		if srclooplen > 0:
			output[w] |= FLAG_LOOP
			var lc_filter := (output[w_loop] & 12) >> 2
			if lc_filter == 0:
				return false
			var lc_range := (output[w_loop] & 240) >> 4
			var lc_value := output[w_loop + 1] >> 4
			lc_value <<= lc_range
			lc_value += _filter(sbuffer[15], sbuffer[14], lc_filter)
			if absi(lc_value - loop_v1) > LOOP_LOSS_TOLERANCE:
				a = srcloop
				w = w_loop
				redo = true
				use_filter0 = true
	return false


## smconv's BRR_CompressBlock: tries every filter (or just [param fixed]
## when it is below 4) and every range, and keeps the one with the least
## error. [param buffer] holds the two previous decoded samples then the
## 16 to encode.
static func _compress_block(buffer: PackedInt32Array, fixed: int) -> Dictionary:
	var fmin := 0 if fixed == 4 else fixed
	var fmax := 3 if fixed == 4 else fixed
	var best_error := 2147483647
	var best_range := 0
	var best_filter := 0
	var best_data := PackedInt32Array()
	best_data.resize(16)
	var best_samp := PackedInt32Array()
	best_samp.resize(18)
	var block_data := PackedInt32Array()
	block_data.resize(16)
	var block_samp := PackedInt32Array()
	block_samp.resize(16)
	for filter in range(fmin, fmax + 1):
		for r_shift in range(12, -1, -1):
			var r_half := (1 << r_shift) >> 1
			var c_1 := buffer[1]
			var c_2 := buffer[0]
			var block_error := 0
			for x in 16:
				var cp := _filter(c_2, c_1, filter)
				var c := buffer[x + 2] >> 1
				var s1 := _s16(c & 0x7FFF)
				var s2 := _s16(c | 0x8000)
				s1 -= cp
				s2 -= cp
				s1 <<= 1
				s2 <<= 1
				s1 += r_half
				s2 += r_half
				s1 >>= r_shift
				s2 >>= r_shift
				s1 = clampi(s1, -8, 7)
				s2 = clampi(s2, -8, 7)
				var rs1 := s1
				var rs2 := s2
				s1 = (s1 << r_shift) >> 1
				s2 = (s2 << r_shift) >> 1
				if filter >= 2:
					s1 = clampi(s1 + cp, -32768, 32767)
					s2 = clampi(s2 + cp, -32768, 32767)
				else:
					s1 = s1 + cp
					s2 = s2 + cp
				s1 = _s16(s1 << 1) >> 1
				s2 = _s16(s2 << 1) >> 1
				var ra := absi(c - s1)
				var rb := absi(c - s2)
				if ra < rb:
					block_error += ra
					block_data[x] = rs1
				else:
					block_error += rb
					block_data[x] = rs2
					s1 = s2
				if block_data[x] < 0:
					block_data[x] += 16
				c_2 = c_1
				c_1 = s1
				block_samp[x] = s1
			if block_error < best_error:
				best_error = block_error
				best_range = r_shift
				best_filter = filter
				for x in 16:
					best_data[x] = block_data[x]
					best_samp[x + 2] = block_samp[x]
	best_samp[0] = best_samp[16]
	best_samp[1] = best_samp[17]
	var overflow := false
	for x in 16:
		if _test_overflow(best_samp, x):
			overflow = true
	var samp := PackedInt32Array()
	samp.resize(16)
	for x in 16:
		samp[x] = best_samp[x + 2]
	return {"data": best_data, "samp": samp, "range": best_range, "filter": best_filter, "overflow": overflow}


## A 16-bit value read as signed, as C's (signed short) cast does.
static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


## smconv's ComputeFilter: the prediction from the two previous samples.
static func _filter(x_2: int, x_1: int, filter: int) -> int:
	match filter:
		1:
			return x_1 + ((-x_1) >> 4)
		2:
			return (x_1 << 1) + ((-(x_1 + (x_1 << 1))) >> 5) - x_2 + (x_2 >> 4)
		3:
			return (x_1 << 1) + ((-(x_1 + (x_1 << 2) + (x_1 << 3))) >> 6) - x_2 + ((x_2 + (x_2 << 1)) >> 4)
	return 0


## smconv's overflow test: would Gaussian interpolation of three neighbouring
## samples leave the DSP's range at the three worst positions?
static func _test_overflow(ls: PackedInt32Array, i: int) -> bool:
	return _gauss_overflow(ls, i, 370, 1305, 374) or _gauss_overflow(ls, i, 366, 1305, 378) or _gauss_overflow(ls, i, 336, 1303, 410)


static func _gauss_overflow(ls: PackedInt32Array, i: int, g4: int, g3: int, g2: int) -> bool:
	var s := (g4 * ls[i]) >> 11
	s += (g3 * ls[i + 1]) >> 11
	s += (g2 * ls[i + 2]) >> 11
	return s > 0x3FFF or s < -0x4000


## Decodes BRR as the S-DSP does, into the values it interpolates between
## (16-bit, always even). Plays the data once to its end block, then, if
## that block loops, the loop [param loop_passes] more times, so the
## filters' history carries over the loop point as on the console. Returns
## {pcm: PackedInt32Array, loop: index of the loop's first sample in the
## last pass, or -1}.
static func decode(data: PackedByteArray, loop_offset := 0, loop_passes := 1) -> Dictionary:
	var pcm := PackedInt32Array()
	var p1 := 0
	var p2 := 0
	var at := 0
	var loop_index := -1
	var passes := 0
	while at + BLOCK_BYTES <= data.size():
		var header := data[at]
		var shift := header >> 4
		var filter := (header >> 2) & 3
		for i in 16:
			var byte := data[at + 1 + i / 2]
			var n := (byte >> 4) if i % 2 == 0 else (byte & 15)
			if n >= 8:
				n -= 16
			var s: int
			if shift <= 12:
				s = (n << shift) >> 1
			else:
				s = -2048 if n < 0 else 0
			# The DSP works on 15-bit values (shown doubled): predict from the
			# two previous ones, clamp to 16 bits, then wrap to 15.
			s += _filter(p2, p1, filter)
			s = _s16(clampi(s, -32768, 32767) << 1) >> 1
			p2 = p1
			p1 = s
			pcm.append(s << 1)
		if header & FLAG_END:
			if not (header & FLAG_LOOP) or passes >= loop_passes:
				break
			passes += 1
			loop_index = pcm.size()
			at = loop_offset
		else:
			at += BLOCK_BYTES
	if loop_index >= 0:
		return {"pcm": pcm, "loop": loop_index}
	return {"pcm": pcm, "loop": -1}
