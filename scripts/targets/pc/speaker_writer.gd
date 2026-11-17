class_name SpeakerWriter
extends RefCounted
## Writes PC speaker songs and sounds as data for DOS programs, with a small
## MIT-licensed C player (speaker.c) for Open Watcom or Turbo C.
##
## The data is the speaker's pitch 140 times a second: one 16-bit PIT
## divisor (0 is silence) per tick. (Run-length pairs come out larger, as
## the lead and bass take turns every tick.) The player speeds the timer
## interrupt up to 140 Hz, plays the divisors, still calls the BIOS's own handler 18.2 times a second, and can
## play a sound effect over the music.

const RATE := 140


## A speaker stand-in that keeps the divisors played on it.
class Recorder:
	extends RefCounted

	var slots := PackedInt32Array()
	var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0])

	func write_frame(first: int, second: int) -> void:
		slots.append(first)
		slots.append(second)

	func reset() -> void:
		pass

	func set_gain(_channel: int, _gain: float) -> void:
		pass


## Plays [param song] once through. Returns {slots: a divisor per 1/140 s,
## loop_slot: where the loop starts, or -1}.
static func record(song: SpeakerSong) -> Dictionary:
	var rec := Recorder.new()
	var player := SpeakerPlayer.new(song, rec)
	for f in song.frames_before(song.row_count):
		player.tick()
	var loop_slot := song.frames_before(song.loop_start_row) * SpeakerSong.SLOTS if song.looping else -1
	return {"slots": rec.slots, "loop_slot": loop_slot}


## The divisors as little-endian 16-bit words, for programs that load files.
static func bin_bytes(slots: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(slots.size() * 2)
	for k in slots.size():
		out.encode_u16(k * 2, slots[k])
	return out


## A C header holding one song or sound: a divisor per tick, the number of
## ticks and the tick the loop starts on (-1 for none).
static func c_header(symbol: String, slots: PackedInt32Array, loop_slot: int, comment: String) -> String:
	var upper := symbol.to_upper()
	var lines: PackedStringArray = [
		"/* %s */" % comment,
		"/* PC speaker data for speaker.c: a PIT divisor (0 is silence) per */",
		"/* 1/140 s tick. Made with Chiptune Forge. */",
		"#ifndef %s_H" % upper,
		"#define %s_H" % upper,
		"",
		"#include \"speaker.h\"",
		"",
		"#define %s_TICKS %d" % [upper, slots.size()],
		"#define %s_LOOP %d" % [upper, loop_slot],
		"",
		"static const unsigned short SPEAKER_FAR %s[] = {" % symbol,
	]
	var row := PackedStringArray()
	for d in slots:
		row.append(str(d))
		if row.size() == 16:
			lines.append("\t" + ",".join(row) + ",")
			row.clear()
	if not row.is_empty():
		lines.append("\t" + ",".join(row) + ",")
	if slots.is_empty():
		lines.append("\t0")
	lines.append("};")
	lines.append("")
	lines.append("#endif")
	return "\n".join(lines) + "\n"


static func player_header() -> String:
	return """/* speaker.h: a PC speaker music and sound effect player for DOS.
 * Made with Chiptune Forge. MIT licence: use it in anything.
 *
 * Songs and sounds are arrays of 16-bit PIT divisors (1193182 / frequency,
 * or 0 for silence), one per 1/140 s tick. speaker_start speeds the timer interrupt up to 140 Hz and plays
 * them; the BIOS clock still ticks 18.2 times a second.
 */
#ifndef SPEAKER_H
#define SPEAKER_H

#ifndef SPEAKER_FAR
#if defined(__WATCOMC__)
#define SPEAKER_FAR __far
#else
#define SPEAKER_FAR far
#endif
#endif

/* Installs the timer handler. Call once before playing anything. */
void speaker_start(void);
/* Silences the speaker and puts the timer back. Call before exiting. */
void speaker_stop(void);
/* Plays a song: the array from its header, its _TICKS and its _LOOP (-1 to
 * play once). */
void speaker_play(const unsigned short SPEAKER_FAR *song, unsigned ticks, int loop_tick);
/* Plays a sound effect over the music, which carries on underneath and
 * comes back when the sound ends. */
void speaker_sfx(const unsigned short SPEAKER_FAR *sound, unsigned ticks);
/* Stops the music. */
void speaker_halt(void);
/* Nonzero while the music plays. */
int speaker_playing(void);

#endif
"""


static func player_source() -> String:
	return """/* speaker.c: a PC speaker music and sound effect player for DOS.
 * Made with Chiptune Forge. MIT licence: use it in anything.
 * Builds with Open Watcom (wcl -bt=dos) and Turbo C / Borland C.
 */
#include <dos.h>
#include <conio.h>
#include "speaker.h"

#if defined(__WATCOMC__)
#define INTERRUPT __interrupt __far
#define CHAIN(handler) _chain_intr(handler)
#else
#define INTERRUPT interrupt far
#define _disable disable
#define _enable enable
#define _dos_getvect getvect
#define _dos_setvect setvect
#define outp outportb
#define inp inportb
#define CHAIN(handler) (*(handler))()
#endif

#define PIT_HZ 1193182L
#define RATE 140
#define TIMER_DIVISOR ((unsigned)(PIT_HZ / RATE))

typedef struct {
	const unsigned short SPEAKER_FAR *data;
	unsigned ticks;
	int loop;
	unsigned pos;
	unsigned divisor;
	int active;
} Track;

static void (INTERRUPT *old_timer)(void);
static volatile Track music;
static volatile Track effect;
static unsigned long bios_count;
static unsigned sounding = 0xFFFF;
static int installed;

static void tone(unsigned divisor)
{
	if (divisor == sounding)
		return;
	sounding = divisor;
	if (divisor) {
		outp(0x43, 0xB6);
		outp(0x42, divisor & 0xFF);
		outp(0x42, divisor >> 8);
		outp(0x61, inp(0x61) | 3);
	} else {
		outp(0x61, inp(0x61) & 0xFC);
	}
}

/* Moves a track on by one tick. */
static void advance(volatile Track *t)
{
	if (!t->active)
		return;
	if (t->pos >= t->ticks) {
		if (t->loop < 0 || (unsigned)t->loop >= t->ticks) {
			t->active = 0;
			t->divisor = 0;
			return;
		}
		t->pos = (unsigned)t->loop;
	}
	t->divisor = t->data[t->pos++];
}

static void INTERRUPT timer(void)
{
	advance(&music);
	advance(&effect);
	tone(effect.active ? effect.divisor : (music.active ? music.divisor : 0));
	bios_count += TIMER_DIVISOR;
	if (bios_count >= 0x10000L) {
		bios_count -= 0x10000L;
		CHAIN(old_timer);
	} else {
		outp(0x20, 0x20);
	}
}

static void set_timer(unsigned divisor)
{
	outp(0x43, 0x36);
	outp(0x40, divisor & 0xFF);
	outp(0x40, divisor >> 8);
}

void speaker_start(void)
{
	if (installed)
		return;
	_disable();
	music.active = 0;
	effect.active = 0;
	old_timer = _dos_getvect(8);
	_dos_setvect(8, timer);
	set_timer(TIMER_DIVISOR);
	installed = 1;
	_enable();
}

void speaker_stop(void)
{
	if (!installed)
		return;
	_disable();
	set_timer(0);
	_dos_setvect(8, old_timer);
	music.active = 0;
	effect.active = 0;
	outp(0x61, inp(0x61) & 0xFC);
	sounding = 0xFFFF;
	installed = 0;
	_enable();
}

static void begin(volatile Track *t, const unsigned short SPEAKER_FAR *data, unsigned ticks, int loop)
{
	_disable();
	t->data = data;
	t->ticks = ticks;
	t->loop = loop;
	t->pos = 0;
	t->divisor = 0;
	t->active = ticks > 0;
	_enable();
}

void speaker_play(const unsigned short SPEAKER_FAR *song, unsigned ticks, int loop_tick)
{
	begin(&music, song, ticks, loop_tick);
}

void speaker_sfx(const unsigned short SPEAKER_FAR *sound, unsigned ticks)
{
	begin(&effect, sound, ticks, -1);
}

void speaker_halt(void)
{
	_disable();
	music.active = 0;
	_enable();
}

int speaker_playing(void)
{
	return music.active;
}
"""


## An example program: plays the song until a key is pressed, and with
## sounds, plays sound N when key N is pressed.
static func example_source(song_header: String, song_symbol: String, sounds: Array) -> String:
	var lines: PackedStringArray = [
		"/* An example: plays the song until Esc. Made with Chiptune Forge. */",
		"#include <stdio.h>",
		"#include <conio.h>",
		"#include \"speaker.h\"",
	]
	if song_header != "":
		lines.append("#include \"%s\"" % song_header)
	for s in sounds:
		lines.append("#include \"%s.h\"" % s)
	lines.append_array([
		"",
		"int main(void)",
		"{",
		"\tint key = 0;",
		"\tspeaker_start();",
	])
	if song_symbol != "":
		var upper := song_symbol.to_upper()
		lines.append("\tspeaker_play(%s, %s_TICKS, %s_LOOP);" % [song_symbol, upper, upper])
	lines.append("\tprintf(\"Playing on the PC speaker. %s\\n\");" % ("Keys 1 to %d play the sounds. Esc quits." % sounds.size() if not sounds.is_empty() else "Esc quits."))
	lines.append("\twhile (key != 27) {")
	lines.append("\t\tkey = getch();")
	for i in sounds.size():
		var sym := str(sounds[i])
		lines.append("\t\tif (key == '%d')" % (i + 1))
		lines.append("\t\t\tspeaker_sfx(%s, %s_TICKS);" % [sym, sym.to_upper()])
	lines.append_array([
		"\t}",
		"\tspeaker_stop();",
		"\treturn 0;",
		"}",
	])
	return "\n".join(lines) + "\n"


## A makefile for Open Watcom's wmake.
static func makefile(target: String) -> String:
	return "\n".join([
		"# Builds %s.EXE with Open Watcom: wmake" % target.to_upper(),
		"# (Turbo C: tcc -ml -e%s main.c speaker.c)" % target,
		"",
		"%s.exe: main.c speaker.c speaker.h" % target,
		"\twcl -q -bt=dos -ml -fe=$@ main.c speaker.c",
		"",
	])


## How to use the export, for the README inside the zip.
static func readme(prefix: String, symbol: String, ticks: int, sounds: bool, names: Array = []) -> String:
	var lines: PackedStringArray = [
		"%s: %s for the PC speaker" % [prefix, "sound effects" if sounds else "music"],
		"",
		"Files:",
	]
	if sounds:
		for n in names:
			lines.append("  %s.h / %s.bin  One sound: a PIT divisor per 1/140 s tick." % [n, n])
	else:
		lines.append("  %s.h    The song as C data: a PIT divisor (0 is silence) for each of" % symbol)
		lines.append("  %s      its %d ticks of 1/140 s, with %s_TICKS and %s_LOOP." % [" ".repeat(symbol.length()), ticks, symbol.to_upper(), symbol.to_upper()])
		lines.append("  %s.bin  The same divisors as little-endian 16-bit words." % symbol)
	lines.append_array([
		"  speaker.c, speaker.h  The player (MIT): speaker_start, speaker_play, speaker_sfx,",
		"                        speaker_halt and speaker_stop. It runs the timer at 140 Hz",
		"                        and keeps the BIOS clock right.",
		"  main.c, makefile      An example. Build with Open Watcom (wmake, or",
		"                        wcl -bt=dos -ml -fe=play.exe main.c speaker.c) or Turbo C",
		"                        (tcc -ml main.c speaker.c), and run it in DOS or DOSBox.",
		"",
		"Call speaker_start() once, speaker_play(data, TICKS, LOOP) for music and",
		"speaker_sfx(data, TICKS) for a sound over it, and speaker_stop() before exiting.",
	])
	return "\n".join(lines) + "\n"
