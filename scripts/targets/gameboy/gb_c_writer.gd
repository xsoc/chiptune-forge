class_name GbCWriter
extends RefCounted
## Writes Game Boy exports as C for GBDK-2020: songs in hUGEDriver's format
## (the same layout hUGETracker's "GBDK .c" export uses), sound effects for
## the small cf_sfx player, and example projects that build into a ROM.

const DRIVER_DIR := "res://assets/gameboy/hUGEDriver"
const DRIVER_FILES: PackedStringArray = [
	"hUGEDriver.asm",
	"include/hUGEDriver.h",
	"include/hUGE.inc",
	"include/hUGE_note_table.inc",
	"include/hardware.inc",
	"tools/rgb2sdas.py",
	"README.md",
]
## Built by CI (tools/build_hugedriver.sh) and bundled when present.
const DRIVER_LIB := "lib/hUGEDriver.lib"
const NOTE_NAMES: PackedStringArray = ["C_", "Cs", "D_", "Ds", "E_", "F_", "Fs", "G_", "Gs", "A_", "As", "B_"]


## C symbol for a song: lower case, starting with "song_".
static func song_symbol(prefix: String) -> String:
	var base := ExportJob.sanitize(prefix)
	return base if base.begins_with("song") else "song_" + base


## Files for a song: the data (.c), its header and nothing else.
static func song_files(gb: GbSong, symbol: String, credit: String) -> Dictionary:
	return {
		"src/%s.c" % symbol: song_source(gb, symbol, credit).to_utf8_buffer(),
		"src/%s.h" % symbol: song_header(gb, symbol).to_utf8_buffer(),
	}


## A complete GBDK-2020 project that plays the song: data, example main.c,
## Makefile, README, the cf_sfx player and hUGEDriver.
static func song_project(gb: GbSong, symbol: String, title: String, credit: String) -> Dictionary:
	var files := song_files(gb, symbol, credit)
	var sfx_demo := gb.sfx_channel >= 0
	files["src/main.c"] = _song_main(gb, symbol, title).to_utf8_buffer()
	if sfx_demo:
		files["src/cf_sfx.h"] = CF_SFX_H.to_utf8_buffer()
		files["src/cf_sfx.c"] = CF_SFX_C.to_utf8_buffer()
	var sources := "src/main.c src/%s.c" % symbol + (" src/cf_sfx.c" if sfx_demo else "")
	files["Makefile"] = _makefile(symbol, title, sources, true).to_utf8_buffer()
	files["README.txt"] = _song_readme(gb, symbol, title).to_utf8_buffer()
	_add_driver(files)
	return files


## A GBDK-2020 project for a sound kit: the sounds, the cf_sfx player and an
## example that plays each one.
static func sfx_project(sounds: Array, kit_symbol: String, title: String) -> Dictionary:
	var files := {}
	files["src/%s.c" % kit_symbol] = sfx_source(sounds, kit_symbol).to_utf8_buffer()
	files["src/%s.h" % kit_symbol] = sfx_header(sounds, kit_symbol).to_utf8_buffer()
	files["src/cf_sfx.h"] = CF_SFX_H.to_utf8_buffer()
	files["src/cf_sfx.c"] = CF_SFX_C.to_utf8_buffer()
	files["src/main.c"] = _sfx_main(sounds, kit_symbol, title).to_utf8_buffer()
	files["Makefile"] = _makefile(kit_symbol, title, "src/main.c src/%s.c src/cf_sfx.c" % kit_symbol, false).to_utf8_buffer()
	files["README.txt"] = _sfx_readme(sounds, kit_symbol).to_utf8_buffer()
	return files


static func note_name(note: int) -> String:
	if note < 0 or note >= GbSong.LAST_NOTE:
		return "___"
	return "%s%d" % [NOTE_NAMES[note % 12], 3 + note / 12]


static func song_source(gb: GbSong, symbol: String, credit: String) -> String:
	var tracks := gb.build_tracks()
	var patterns: Array = tracks["patterns"]
	var orders: Array = tracks["orders"]
	var out := PackedStringArray()
	out.append("// %s" % _comment(gb.title))
	for line in credit.split("\n"):
		out.append("// %s" % _comment(line))
	out.append("// hUGEDriver song data, as hUGETracker's GBDK export lays it out.")
	out.append("")
	out.append("#include \"hUGEDriver.h\"")
	out.append("#include <stddef.h>")
	out.append("#include \"%s.h\"" % symbol)
	out.append("")
	out.append("static const unsigned char order_cnt = %d;" % (orders[0].size() * 2))
	out.append("")
	for i in patterns.size():
		var rows: PackedInt32Array = patterns[i]
		out.append("static const unsigned char P%d[] = {" % i)
		for r in rows.size() / 4:
			var note := rows[r * 4]
			var effect := (rows[r * 4 + 2] << 8) | rows[r * 4 + 3]
			out.append("    DN(%s,%d,0x%03X)," % [note_name(note), rows[r * 4 + 1], effect])
		out.append("};")
	out.append("")
	for c in 4:
		var names := PackedStringArray()
		for index in orders[c]:
			names.append("P%d" % int(index))
		out.append("static const unsigned char* const order%d[] = {%s};" % [c + 1, ",".join(names)])
	out.append("")
	out.append("static const hUGEDutyInstr_t duty_instruments[] = {")
	for inst in gb.duty_instruments:
		var b := GbSong.duty_bytes(inst)
		out.append("    {%d,%d,%d,NULL,%d}, // %s" % [b[0], b[1], b[2], b[3], _comment(str(inst.get("name", "")))])
	out.append("};")
	out.append("static const hUGEWaveInstr_t wave_instruments[] = {")
	for inst in gb.wave_instruments:
		var b := GbSong.wave_bytes(inst)
		out.append("    {%d,%d,%d,NULL,%d}, // %s" % [b[0], b[1], b[2], b[3], _comment(str(inst.get("name", "")))])
	out.append("};")
	out.append("static const hUGENoiseInstr_t noise_instruments[] = {")
	for inst in gb.noise_instruments:
		var b := GbSong.noise_bytes(inst)
		out.append("    {%d,NULL,%d,0,0}, // %s" % [b[0], b[1], _comment(str(inst.get("name", "")))])
	out.append("};")
	out.append("")
	out.append("static const unsigned char waves[] = {")
	for w in gb.waves.size():
		var ram := gb.wave_ram(w)
		var bytes := PackedStringArray()
		for v in ram:
			bytes.append(str(v))
		out.append("    %s," % ",".join(bytes))
	out.append("};")
	out.append("")
	out.append("const hUGESong_t %s = {%d, &order_cnt, order1, order2, order3, order4, duty_instruments, wave_instruments, noise_instruments, NULL, waves};" % [symbol, gb.ticks_per_row])
	out.append("")
	return "\n".join(out)


static func song_header(gb: GbSong, symbol: String) -> String:
	var up := symbol.to_upper()
	var sfx := "HT_CH%d" % (gb.sfx_channel + 1) if gb.sfx_channel >= 0 else "-1"
	return "\n".join([
		"// %s" % _comment(gb.title),
		"#ifndef %s_H" % up,
		"#define %s_H" % up,
		"",
		"#include \"hUGEDriver.h\"",
		"",
		"extern const hUGESong_t %s;" % symbol,
		"",
		"// The tempo comes from the timer: call hUGE_dosound from the timer",
		"// interrupt with TMA and TAC set to these (see main.c). That gives",
		"// %.2f ticks a second, %d ticks per row: %.1f BPM." % [gb.tick_hz, gb.ticks_per_row, gb.get_bpm()],
		"#define %s_TMA 0x%02X" % [up, gb.timer_tma],
		"#define %s_TAC 0x%02X" % [up, gb.timer_tac],
		"",
		"// The channel game sound effects may interrupt (mute it with",
		"// hUGE_mute_channel while one plays), or -1 for none.",
		"#define %s_SFX_CHANNEL %s" % [up, sfx],
		"",
		"#endif",
		"",
	])


static func sfx_source(sounds: Array, kit_symbol: String) -> String:
	var out := PackedStringArray()
	out.append("// Sound effects for the cf_sfx player. Made with Chiptune Forge.")
	out.append("// You own these sounds and may use them for any purpose.")
	out.append("")
	out.append("#include \"cf_sfx.h\"")
	out.append("#include \"%s.h\"" % kit_symbol)
	out.append("")
	for sound in sounds:
		var gb_sfx: GbSfx = sound
		var id := sfx_symbol(gb_sfx.name)
		out.append("// %s: %d frames on %s%s" % [_comment(gb_sfx.name), gb_sfx.frame_count(), "Pulse 2" if gb_sfx.channel == GbSfx.PULSE else "Noise", (" (" + ", ".join(gb_sfx.notes) + ")") if not gb_sfx.notes.is_empty() else ""])
		out.append("static const uint8_t %s_data[] = {" % id.to_lower())
		for f in gb_sfx.frame_count():
			out.append("    0x%02X,0x%02X,0x%02X," % [gb_sfx.frames[f * 3], gb_sfx.frames[f * 3 + 1], gb_sfx.frames[f * 3 + 2]])
		out.append("};")
		out.append("const cf_sfx_t %s = {%d, %d, %s_data};" % [id, gb_sfx.channel, gb_sfx.frame_count(), id.to_lower()])
		out.append("")
	return "\n".join(out)


static func sfx_header(sounds: Array, kit_symbol: String) -> String:
	var up := kit_symbol.to_upper()
	var out := PackedStringArray(["#ifndef %s_H" % up, "#define %s_H" % up, "", "#include \"cf_sfx.h\"", ""])
	for sound in sounds:
		out.append("extern const cf_sfx_t %s;" % sfx_symbol((sound as GbSfx).name))
	out.append("")
	out.append("#define %s_COUNT %d" % [up, sounds.size()])
	out.append("")
	out.append("#endif")
	out.append("")
	return "\n".join(out)


## C name for a sound, such as SFX_COIN.
static func sfx_symbol(sound_name: String) -> String:
	var base := ExportJob.sanitize(sound_name).to_upper()
	return base if base.begins_with("SFX_") else "SFX_" + base


static func _add_driver(files: Dictionary) -> void:
	for path in DRIVER_FILES:
		var bytes := FileAccess.get_file_as_bytes(DRIVER_DIR.path_join(path))
		if not bytes.is_empty():
			files["hUGEDriver/" + path] = bytes
	var lib := FileAccess.get_file_as_bytes(DRIVER_DIR.path_join(DRIVER_LIB))
	if not lib.is_empty():
		files["hUGEDriver/" + DRIVER_LIB] = lib


static func has_bundled_driver() -> bool:
	return FileAccess.file_exists(DRIVER_DIR.path_join(DRIVER_LIB))


static func _comment(text: String) -> String:
	return text.replace("*/", "* /").replace("\n", " ").strip_edges()


## Text for a C string literal: printable ASCII only, escaped.
static func _c_string(text: String, limit := 18) -> String:
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 32 or code > 126:
			continue
		var c := char(code)
		if c == "\\" or c == "\"":
			out += "\\"
		out += c
		if out.length() >= limit:
			break
	return out


static func _rom_title(title: String) -> String:
	var out := ""
	for c in title.to_upper():
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == " ":
			out += c
	return out.substr(0, 11).strip_edges() if out.strip_edges() != "" else "CHIPFORGE"


static func _makefile(symbol: String, title: String, sources: String, with_driver: bool) -> String:
	var lines := PackedStringArray([
		"# Builds %s.gb with GBDK-2020: https://github.com/gbdk-2020/gbdk-2020" % symbol,
		"# Set GBDK_HOME to the folder you unpacked GBDK into, for example",
		"#   make GBDK_HOME=~/gbdk",
		"",
		"GBDK_HOME ?= ../gbdk",
		"LCC = $(GBDK_HOME)/bin/lcc",
		"ROM = %s.gb" % symbol,
		"SRC = %s" % sources,
	])
	if with_driver:
		lines.append_array([
			"DRIVER = hUGEDriver",
			"DRIVER_LIB = $(DRIVER)/lib/hUGEDriver.lib",
			"",
			"all: $(ROM)",
			"",
			"$(ROM): $(SRC) $(DRIVER_LIB)",
			"\t$(LCC) -I$(DRIVER)/include -Isrc -Wl-l$(DRIVER_LIB) -Wm-yn\"%s\" -o $@ $(SRC)" % _rom_title(title),
			"",
			"# Only needed when the export came without a prebuilt driver: building",
			"# hUGEDriver for GBDK takes RGBDS 0.6 (https://rgbds.gbdev.io) and Python 3.",
			"$(DRIVER_LIB):",
			"\tmkdir -p $(DRIVER)/lib",
			"\trgbasm -DGBDK -i$(DRIVER)/ -o $(DRIVER)/lib/hUGEDriver.obj $(DRIVER)/hUGEDriver.asm",
			"\tpython3 $(DRIVER)/tools/rgb2sdas.py -o $(DRIVER)/lib/hUGEDriver.o $(DRIVER)/lib/hUGEDriver.obj",
			"\t$(GBDK_HOME)/bin/sdar -ru $@ $(DRIVER)/lib/hUGEDriver.o",
		])
	else:
		lines.append_array([
			"",
			"all: $(ROM)",
			"",
			"$(ROM): $(SRC)",
			"\t$(LCC) -DCF_SFX_NO_HUGE -Isrc -Wm-yn\"%s\" -o $@ $(SRC)" % _rom_title(title),
		])
	lines.append_array([
		"",
		"clean:",
		"\trm -f $(ROM) *.o *.ihx *.map *.noi *.sym *.lst *.asm",
		"",
		".PHONY: all clean",
		"",
	])
	return "\n".join(lines)


static func _song_main(gb: GbSong, symbol: String, title: String) -> String:
	var up := symbol.to_upper()
	var sfx := gb.sfx_channel >= 0
	var lines := PackedStringArray([
		"// Plays the song with hUGEDriver. Made with Chiptune Forge.",
		"#include <gb/gb.h>",
		"#include <stdint.h>",
		"#include <stdio.h>",
		"#include \"hUGEDriver.h\"",
		"#include \"%s.h\"" % symbol,
	])
	if sfx:
		lines.append("#include \"cf_sfx.h\"")
		lines.append("")
		lines.append("// A short test sound on the channel the song leaves for effects.")
		if gb.sfx_channel == 1:
			lines.append("static const uint8_t demo_data[] = {")
			lines.append("    0xC6,0x7B,0x07, 0xC2,0x7B,0x07, 0xB6,0x7B,0x07, 0xA6,0x9D,0x07,")
			lines.append("    0x96,0x9D,0x07, 0x86,0x9D,0x07, 0x76,0x9D,0x07, 0x66,0x9D,0x07,")
			lines.append("    0x56,0x9D,0x07, 0x46,0x9D,0x07, 0x36,0x9D,0x07, 0x26,0x9D,0x07,")
			lines.append("    0x16,0x9D,0x07,")
			lines.append("};")
			lines.append("static const cf_sfx_t demo_sfx = {1, 13, demo_data};")
		else:
			lines.append("static const uint8_t demo_data[] = {")
			lines.append("    0xF4,0x45,0x00, 0xD4,0x45,0x00, 0xB4,0x46,0x00, 0x94,0x46,0x00,")
			lines.append("    0x74,0x47,0x00, 0x54,0x47,0x00, 0x34,0x57,0x00, 0x14,0x57,0x00,")
			lines.append("};")
			lines.append("static const cf_sfx_t demo_sfx = {3, 8, demo_data};")
	lines.append_array([
		"",
		"void main(void) {",
		"    // Sound on, both speakers, full volume.",
		"    NR52_REG = 0x80;",
		"    NR51_REG = 0xFF;",
		"    NR50_REG = 0x77;",
		"",
		"    printf(\"\\n %s\\n\\n Made with\\n Chiptune Forge\\n\");" % _c_string(title),
	])
	if sfx:
		lines.append("    printf(\"\\n A: test sound\\n\");")
	lines.append_array([
		"",
		"    // The driver ticks from the timer interrupt, at the song's tempo.",
		"    __critical {",
		"        hUGE_init(&%s);" % symbol,
		"        add_TIM(hUGE_dosound);",
		"        TMA_REG = %s_TMA;" % up,
		"        TAC_REG = %s_TAC;" % up,
		"    }",
		"    set_interrupts(VBL_IFLAG | TIM_IFLAG);",
		"",
	])
	if sfx:
		lines.append_array([
			"    uint8_t keys = 0, last = 0;",
			"    while (1) {",
			"        wait_vbl_done();",
			"        keys = joypad();",
			"        if ((keys & J_A) && !(last & J_A)) cf_sfx_play(&demo_sfx);",
			"        last = keys;",
			"        cf_sfx_update();",
			"    }",
		])
	else:
		lines.append_array([
			"    while (1) {",
			"        wait_vbl_done();",
			"    }",
		])
	lines.append("}")
	lines.append("")
	return "\n".join(lines)


static func _sfx_main(sounds: Array, kit_symbol: String, title: String) -> String:
	var names := PackedStringArray()
	var ptrs := PackedStringArray()
	for sound in sounds:
		names.append("\"%s\"" % _c_string((sound as GbSfx).name, 14))
		ptrs.append("&" + sfx_symbol((sound as GbSfx).name))
	return "\n".join([
		"// Plays each sound in the kit. Made with Chiptune Forge.",
		"#include <gb/gb.h>",
		"#include <gbdk/console.h>",
		"#include <stdint.h>",
		"#include <stdio.h>",
		"#include \"cf_sfx.h\"",
		"#include \"%s.h\"" % kit_symbol,
		"",
		"static const char * const names[] = {%s};" % ", ".join(names),
		"static const cf_sfx_t * const sounds[] = {%s};" % ", ".join(ptrs),
		"",
		"void main(void) {",
		"    NR52_REG = 0x80;",
		"    NR51_REG = 0xFF;",
		"    NR50_REG = 0x77;",
		"    printf(\"\\n %s\\n\\n UP/DOWN: pick\\n A: play\\n\");" % _c_string(title),
		"    uint8_t index = 0, shown = 255, keys = 0, last = 0, pressed;",
		"    while (1) {",
		"        wait_vbl_done();",
		"        keys = joypad();",
		"        pressed = keys & ~last;",
		"        last = keys;",
		"        if ((pressed & J_DOWN) && index + 1 < %s_COUNT) index++;" % kit_symbol.to_upper(),
		"        if ((pressed & J_UP) && index > 0) index--;",
		"        if (pressed & J_A) cf_sfx_play(sounds[index]);",
		"        if (index != shown) {",
		"            shown = index;",
		"            gotoxy(0, 8);",
		"            printf(\"                   \");",
		"            gotoxy(1, 8);",
		"            printf(\"%d: %s\", index + 1, names[index]);",
		"        }",
		"        cf_sfx_update();",
		"    }",
		"}",
		"",
	])


static func _song_readme(gb: GbSong, symbol: String, title: String) -> String:
	var lines := PackedStringArray([
		"%s for the Game Boy" % title,
		"Made with Chiptune Forge. You own this music and may use it for any purpose.",
		"",
		"This folder is a GBDK-2020 project that plays the song with hUGEDriver.",
		"",
		"Build the example ROM",
		"  1. Install GBDK-2020: https://github.com/gbdk-2020/gbdk-2020/releases",
		"  2. In this folder run:  make GBDK_HOME=/path/to/gbdk",
		"  3. Open %s.gb in an emulator (SameBoy, Emulicious, mGBA) or on a flash cart." % symbol,
	])
	if not has_bundled_driver():
		lines.append("  This export has no prebuilt hUGEDriver, so make also builds it, which")
		lines.append("  needs RGBDS 0.6 (https://rgbds.gbdev.io) and Python 3 on your PATH.")
	lines.append_array([
		"",
		"Use the song in your game",
		"  - Copy src/%s.c and src/%s.h into your project." % [symbol, symbol],
		"  - Link hUGEDriver: add -Ipath/to/hUGEDriver/include and",
		"    -Wl-lpath/to/hUGEDriver/lib/hUGEDriver.lib to your lcc command.",
		"  - Start it as src/main.c does: hUGE_init(&%s), then call hUGE_dosound" % symbol,
		"    from the timer interrupt with TMA_REG = %s_TMA and TAC_REG = %s_TAC." % [symbol.to_upper(), symbol.to_upper()],
		"    That plays it at %.1f BPM. (Calling hUGE_dosound from VBlank instead also" % gb.get_bpm(),
		"    works, but plays at %.1f BPM.)" % (59.7275 / gb.ticks_per_row * 15.0),
		"",
	])
	if gb.sfx_channel >= 0:
		lines.append_array([
			"Sound effects",
			"  %s is marked safe for sound effects (%s_SFX_CHANNEL)." % [GbSong.CHANNEL_NAMES[gb.sfx_channel], symbol.to_upper()],
			"  src/cf_sfx.c plays Chiptune Forge sound effects there: it mutes that channel",
			"  in hUGEDriver while a sound plays and gives it back afterwards. Export a",
			"  sound kit for the Game Boy to get more sounds in the same format.",
			"",
		])
	lines.append_array([
		"What changed to fit the Game Boy",
	])
	for line in gb.report:
		lines.append("  - " + line)
	lines.append_array([
		"",
		"hUGEDriver (hUGEDriver/) is by SuperDisk and contributors and is in the public",
		"domain: https://github.com/SuperDisk/hUGEDriver",
		"",
	])
	return "\n".join(lines)


static func _sfx_readme(sounds: Array, kit_symbol: String) -> String:
	var lines := PackedStringArray([
		"Sound kit for the Game Boy",
		"Made with Chiptune Forge. You own these sounds and may use them for any purpose.",
		"",
		"Build the example ROM",
		"  1. Install GBDK-2020: https://github.com/gbdk-2020/gbdk-2020/releases",
		"  2. In this folder run:  make GBDK_HOME=/path/to/gbdk",
		"  3. Open %s.gb in an emulator. Up and Down pick a sound, A plays it." % kit_symbol,
		"",
		"Use the sounds in your game",
		"  - Copy src/cf_sfx.c, src/cf_sfx.h and src/%s.c, src/%s.h into your project." % [kit_symbol, kit_symbol],
		"  - Call cf_sfx_play(&SFX_COIN) to start a sound and cf_sfx_update() once a frame.",
		"  - With hUGEDriver music, cf_sfx mutes the sound's channel in the driver while it",
		"    plays. Without hUGEDriver, compile with -DCF_SFX_NO_HUGE.",
		"",
		"Each sound plays on one channel: Pulse 2 for tones, Noise for noisy sounds.",
		"",
		"Sounds:",
	])
	for sound in sounds:
		var gb_sfx: GbSfx = sound
		var line := "  %s  %s, %.2f s" % [sfx_symbol(gb_sfx.name), "Pulse 2" if gb_sfx.channel == GbSfx.PULSE else "Noise", gb_sfx.frame_count() / GbSfx.FRAME_HZ]
		if not gb_sfx.notes.is_empty():
			line += " (%s)" % ", ".join(gb_sfx.notes)
		lines.append(line)
	lines.append("")
	return "\n".join(lines)


const CF_SFX_H := """// cf_sfx: plays Chiptune Forge sound effects on the Game Boy.
// Part of Chiptune Forge, MIT licence. Copy it into your game freely.
#ifndef CF_SFX_H
#define CF_SFX_H

#include <stdint.h>

// A sound: one register update per frame on one channel.
typedef struct cf_sfx_t {
    uint8_t channel;      // 1 = Pulse 2 (CH2), 3 = Noise (CH4)
    uint8_t frames;       // number of frames
    const uint8_t *data;  // 3 bytes per frame
} cf_sfx_t;

// Starts a sound, stopping any sound already playing.
void cf_sfx_play(const cf_sfx_t *sfx);
// Stops the current sound and gives its channel back to the music.
void cf_sfx_stop(void);
// Call once per frame (after wait_vbl_done).
void cf_sfx_update(void);
// Non-zero while a sound is playing.
uint8_t cf_sfx_playing(void);

#endif
"""

const CF_SFX_C := """// cf_sfx: plays Chiptune Forge sound effects on the Game Boy.
// Part of Chiptune Forge, MIT licence. Copy it into your game freely.
//
// Each frame holds three bytes:
//   0: volume (bits 7-4), retrigger (bit 2), duty (bits 1-0)
//   1: Pulse: period low byte. Noise: NR43 (clock and width).
//   2: Pulse: period high bits.
#include <gb/gb.h>
#include "cf_sfx.h"
#ifndef CF_SFX_NO_HUGE
#include "hUGEDriver.h"
#endif

static const cf_sfx_t *current;
static const uint8_t *next_frame;
static uint8_t frames_left;

void cf_sfx_play(const cf_sfx_t *sfx) {
    if (current) cf_sfx_stop();
    current = sfx;
    next_frame = sfx->data;
    frames_left = sfx->frames;
#ifndef CF_SFX_NO_HUGE
    hUGE_mute_channel(sfx->channel, HT_CH_MUTE);
#endif
}

void cf_sfx_stop(void) {
    if (!current) return;
    if (current->channel == 1) {
        NR22_REG = 0;
    } else {
        NR42_REG = 0;
    }
#ifndef CF_SFX_NO_HUGE
    hUGE_mute_channel(current->channel, HT_CH_PLAY);
#endif
    current = 0;
}

uint8_t cf_sfx_playing(void) {
    return current != 0;
}

void cf_sfx_update(void) {
    if (!current) return;
    if (frames_left == 0) {
        cf_sfx_stop();
        return;
    }
    uint8_t a = next_frame[0];
    uint8_t b = next_frame[1];
    uint8_t c = next_frame[2];
    next_frame += 3;
    frames_left--;
    if (current->channel == 1) {
        NR21_REG = (a & 3) << 6;
        if (a & 4) {
            NR22_REG = a & 0xF0;
            NR23_REG = b;
            NR24_REG = 0x80 | c;
        } else {
            NR23_REG = b;
            NR24_REG = c;
        }
    } else {
        if (a & 4) {
            NR42_REG = a & 0xF0;
            NR43_REG = b;
            NR44_REG = 0x80;
        } else {
            NR43_REG = b;
        }
    }
}
"""
