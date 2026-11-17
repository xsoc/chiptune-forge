class_name SnesSong
extends NesSong
## A song arranged for the SNES, as an Impulse Tracker module for SNESMod,
## the sound driver in PVSnesLib: eight channels of notes on sampled
## instruments, played at SNESMod's tick rate, with the S-DSP's echo.
##
## It keeps [NesSong]'s rows, notes and sections, with these differences:[br]
## - [member notes] has eight channels (see [constant SNES_CHANNEL_NAMES]).
##   Channel 8 stays empty: SNESMod plays sound effects there.[br]
## - A note is an Impulse Tracker note number, which is the MIDI note
##   (60 is middle C). Volumes are Impulse Tracker volumes, 0 to 64.[br]
## - [member groove] is one value, the module's speed (ticks per row), and
##   [member frame_hz] is SNESMod's tick rate for [member tempo].[br]
## - Instruments name a sample from [member samples] and may have a volume
##   envelope in ticks, a fadeout and a vibrato.[br]
## [method rows] lays the notes out as tracker rows with their effects;
## [SnesPlayer] plays those rows as SNESMod does, and [ItWriter] writes
## them as the module.

const CHANNEL_COUNT := 8
const SNES_CHANNEL_NAMES: PackedStringArray = ["Lead", "Harmony", "Arp", "Bass", "Pad 1", "Pad 2", "Drums", "Effects"]
const LEAD := 0
const HARMONY := 1
const ARP := 2
const BASS := 3
const PAD1 := 4
const PAD2 := 5
const DRUMS := 6
## SNESMod plays sound effects on the last voice, so music leaves it free.
const SFX_CHANNEL := 7
## Impulse Tracker note-off and note-cut values.
const NOTE_OFF := 255
const NOTE_CUT := 254
## Effect letters as Impulse Tracker numbers them (A = 1).
const CMD_SPEED := 1
const CMD_JUMP := 2
const CMD_VIBRATO := 8
const CMD_ARPEGGIO := 10
## The S-DSP's pitch register is 14 bits.
const MAX_PITCH := 0x3FFF

## Impulse Tracker tempo: SNESMod ticks [code]8000 / floor(20480 / tempo)[/code]
## times a second.
var tempo := 150
## Sample names from [SnesSamples], in module order.
var samples: PackedStringArray = []
## Panning per channel, 0 (left) to 64 (right).
var pans := PackedInt32Array([32, 32, 32, 32, 32, 32, 32, 32])
## Echo settings, as SNESMod's song message commands take them: {edl
## (0 to 15, 16 ms each), efb, evol (-128 to 127), fir (8 taps), eon
## (bit mask of channels)}.
var echo := {"edl": 0, "efb": 0, "evol": 0, "fir": [127, 0, 0, 0, 0, 0, 0, 0], "eon": 0}

var _rows: Array = []
var _highest := {}


func _init() -> void:
	frame_hz = tick_hz(tempo)
	notes = []
	for c in CHANNEL_COUNT:
		notes.append([])


## SNESMod's tick rate for an Impulse Tracker tempo: its timer runs at 8 kHz
## and counts [code]20480 / tempo[/code] steps per tick.
static func tick_hz(it_tempo: int) -> float:
	return 8000.0 / floor(20480.0 / clampi(it_tempo, 32, 255))


## The speed and tempo that play [param bpm] most closely. Returns {speed,
## tempo, bpm}. Ties go to the tick rate nearest 60 Hz, which gives
## envelopes and vibrato a good resolution.
static func choose_tempo(bpm: float, steps_per_beat: int) -> Dictionary:
	var rows_per_second := bpm * steps_per_beat / 60.0
	var best := {"speed": 6, "tempo": 150, "bpm": 0.0}
	var best_score := INF
	for speed in range(2, 16):
		for t in range(32, 256):
			var actual := tick_hz(t) / speed * 60.0 / maxf(steps_per_beat, 1)
			var score := absf(actual - bpm) / maxf(bpm, 1.0) * 1000.0 + absf(tick_hz(t) - 60.0) * 0.001
			if score < best_score:
				best_score = score
				best = {"speed": speed, "tempo": t, "bpm": actual}
	return best


func set_tempo(it_tempo: int, speed: int) -> void:
	tempo = it_tempo
	frame_hz = tick_hz(it_tempo)
	groove = PackedInt32Array([speed])


func speed() -> int:
	return groove[0]


## An Impulse Tracker volume (0 to 64) for a level of 0 to 15 in 2 dB steps.
static func volume_of_level(level: int) -> int:
	if level <= 0:
		return 0
	return clampi(roundi(64.0 * pow(10.0, (clampi(level, 0, 15) - 15) * 2.0 / 20.0)), 1, 64)


## Highest note an instrument can play without its pitch passing the
## S-DSP's limit.
func highest_note(instrument: int) -> int:
	if _highest.has(instrument):
		return _highest[instrument]
	var base := SnesSamples.pitch_base(samples[int(instruments[instrument]["sample"])])
	var n := 119
	while n > 0 and dsp_pitch(n * 64 + base) > MAX_PITCH:
		n -= 1
	_highest[instrument] = n
	return n


## The tracker rows: one array per row of [constant CHANNEL_COUNT] cells,
## each null or {note (-1 none), instrument (1-based, 0 none), volume (-1
## none), command (0 none), param}. Notes start with their instrument and
## volume; a note that ends before the next one gets a note-off; arpeggios
## repeat their J command on every row they play, and an instrument's
## vibrato repeats its H command from its delay on. The loop is a jump on
## the last row.
func rows() -> Array:
	if not _rows.is_empty() or row_count == 0:
		return _rows
	_rows.resize(row_count)
	for r in row_count:
		var row: Array = []
		row.resize(CHANNEL_COUNT)
		_rows[r] = row
	for c in CHANNEL_COUNT:
		var list: Array = notes[c]
		for k in list.size():
			var n: Dictionary = list[k]
			var start := int(n["row"])
			var next_start := int(list[k + 1]["row"]) if k + 1 < list.size() else row_count
			var end := mini(start + int(n["length"]), next_start)
			var inst: Dictionary = instruments[int(n["instrument"])]
			_cell(start, c)["note"] = int(n["note"])
			_cell(start, c)["instrument"] = int(n["instrument"]) + 1
			_cell(start, c)["volume"] = int(n["volume"])
			var arp := int(n.get("arp", -1))
			var vibrato: Dictionary = inst.get("vibrato", {})
			for r in range(start, end):
				if arp >= 0:
					_cell(r, c)["command"] = CMD_ARPEGGIO
					_cell(r, c)["param"] = arp_param(arp)
				elif not vibrato.is_empty() and r - start >= int(vibrato["delay"]):
					_cell(r, c)["command"] = CMD_VIBRATO
					_cell(r, c)["param"] = (int(vibrato["speed"]) << 4) | int(vibrato["depth"])
			if end < next_start and end < row_count:
				_cell(end, c)["note"] = NOTE_OFF
	if looping:
		var last := _cell(row_count - 1, SFX_CHANNEL)
		last["command"] = CMD_JUMP
		last["param"] = -1
	return _rows


func _cell(r: int, c: int) -> Dictionary:
	var row: Array = _rows[r]
	if row[c] == null:
		row[c] = {"note": -1, "instrument": 0, "volume": -1, "command": 0, "param": 0}
	return row[c]


## The J command's parameter for arpeggio [param index]: its second and
## third notes, in semitones above the first.
func arp_param(index: int) -> int:
	var values: Array = arpeggios[index]["values"]
	var x := int(values[1]) if values.size() > 1 else 0
	var y := int(values[2]) if values.size() > 2 else 0
	return (clampi(x, 0, 15) << 4) | clampi(y, 0, 15)


## The S-DSP pitch for a SNESMod pitch value (note * 64 plus the sample's
## pitch base), through SNESMod's own frequency table.
static func dsp_pitch(value: int) -> int:
	value &= 0xFFFF
	var octave := (value >> 8) / 3
	var f := value - octave * 768
	var shift := 8 - octave
	if f < 0 or f >= 768 or shift < 0:
		return 0xFFFF
	return _ftab()[f] >> shift


static var _ftab_cache := PackedInt32Array()


static func _ftab() -> PackedInt32Array:
	if _ftab_cache.is_empty():
		for i in 768:
			_ftab_cache.append(FTAB.substr(i * 4, 4).hex_to_int())
	return _ftab_cache


## Source sample count and audio RAM use. Returns {samples, bytes, echo,
## free}: bytes of BRR, bytes the echo buffer takes, and what is left of
## SNESMod's 58 KB.
func ram_use() -> Dictionary:
	var bytes := 0
	for name in samples:
		bytes += SnesSamples.brr_size(name)
	var echo_bytes := int(echo["edl"]) * 2048
	return {"samples": samples.size(), "bytes": bytes, "echo": echo_bytes, "free": RAM_LIMIT - bytes - echo_bytes}


## Audio RAM SNESMod leaves for a module's samples, patterns and echo.
const RAM_LIMIT := 58000

## SNESMod's frequency table (LUT_FTAB in sm_spc.asm): pitch register
## values for one octave in 768 steps, four hex digits each.
const FTAB := (
	"2174217B2183218B2193219A21A221AA21B221BA21C121C921D121D921E121E821F021F82200220822102218221F2227" +
	"222F2237223F2247224F2257225F2267226F2277227F2287228F2297229F22A722AF22B722BF22C722CF22D722DF22E7" +
	"22EF22F722FF2307230F2317231F232823302338234023482350235823612369237123792381238A2392239A23A223AA" +
	"23B323BB23C323CB23D423DC23E423ED23F523FD2406240E2416241F2427242F243824402448245124592462246A2472" +
	"247B2483248C2494249D24A524AE24B624BE24C724CF24D824E024E924F224FA2503250B2514251C2525252D2536253F" +
	"2547255025592561256A2572257B2584258C2595259E25A725AF25B825C125C925D225DB25E425EC25F525FE2607260F" +
	"26182621262A2633263C2644264D2656265F26682671267A2682268B2694269D26A626AF26B826C126CA26D326DC26E5" +
	"26EE26F7270027092712271B2724272D2736273F27482751275A2763276D2776277F27882791279A27A327AC27B627BF" +
	"27C827D127DA27E427ED27F627FF28092812281B2824282E28372840284A2853285C2865286F28782882288B2894289E" +
	"28A728B028BA28C328CD28D628E028E928F228FC2905290F29182922292B2935293E29482951295B2965296E29782981" +
	"298B2995299E29A829B129BB29C529CE29D829E229EB29F529FF2A082A122A1C2A262A2F2A392A432A4D2A562A602A6A" +
	"2A742A7E2A872A912A9B2AA52AAF2AB92AC32ACC2AD62AE02AEA2AF42AFE2B082B122B1C2B262B302B3A2B442B4E2B58" +
	"2B622B6C2B762B802B8A2B942B9E2BA82BB22BBC2BC62BD12BDB2BE52BEF2BF92C032C0D2C182C222C2C2C362C402C4B" +
	"2C552C5F2C692C742C7E2C882C932C9D2CA72CB22CBC2CC62CD12CDB2CE52CF02CFA2D042D0F2D192D242D2E2D392D43" +
	"2D4D2D582D622D6D2D772D822D8C2D972DA12DAC2DB72DC12DCC2DD62DE12DEC2DF62E012E0B2E162E212E2B2E362E41" +
	"2E4B2E562E612E6C2E762E812E8C2E972EA12EAC2EB72EC22ECC2ED72EE22EED2EF82F032F0E2F182F232F2E2F392F44" +
	"2F4F2F5A2F652F702F7B2F862F912F9C2FA72FB22FBD2FC82FD32FDE2FE92FF42FFF300A30153020302C30373042304D" +
	"30583063306E307A30853090309B30A730B230BD30C830D430DF30EA30F53101310C31173123312E313A31453150315C" +
	"31673173317E3189319531A031AC31B731C331CE31DA31E531F131FC32083213321F322B32363242324D325932653270" +
	"327C32883293329F32AB32B732C232CE32DA32E532F132FD330933153320332C333833443350335C33673373337F338B" +
	"339733A333AF33BB33C733D333DF33EB33F73403340F341B34273433343F344B34573463346F347B3488349434A034AC" +
	"34B834C434D134DD34E934F53502350E351A35263533353F354B355835643570357D3589359535A235AE35BA35C735D3" +
	"35E035EC35F936053612361E362B363736443650365D366936763683368F369C36A836B536C236CE36DB36E836F43701" +
	"370E371B372737343741374E375A376737743781378E379A37A737B437C137CE37DB37E837F53802380E381B38283835" +
	"3842384F385C3869387638843891389E38AB38B838C538D238DF38EC38FA390739143921392E393B3949395639633970" +
	"397E398B399839A639B339C039CE39DB39E839F63A033A113A1E3A2B3A393A463A543A613A6F3A7C3A8A3A973AA53AB2" +
	"3AC03ACE3ADB3AE93AF63B043B123B1F3B2D3B3B3B483B563B643B723B7F3B8D3B9B3BA93BB63BC43BD23BE03BEE3BFC" +
	"3C093C173C253C333C413C4F3C5D3C6B3C793C873C953CA33CB13CBF3CCD3CDB3CE93CF73D053D133D213D2F3D3E3D4C" +
	"3D5A3D683D763D853D933DA13DAF3DBD3DCC3DDA3DE83DF73E053E133E223E303E3E3E4D3E5B3E6A3E783E863E953EA3" +
	"3EB23EC03ECF3EDD3EEC3EFA3F093F183F263F353F433F523F613F6F3F7E3F8D3F9B3FAA3FB93FC73FD63FE53FF44002" +
	"40114020402F403E404D405B406A40794088409740A640B540C440D340E240F14100410F411E412D413C414B415A4169" +
	"41784188419741A641B541C441D341E341F2420142104220422F423E424E425D426C427C428B429A42AA42B942C942D8")
