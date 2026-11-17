/*
 * pce_player.c: Chiptune Forge's music and sound effect player for the
 * PC Engine / TurboGrafx-16, for HuCC (https://github.com/pce-devel/huc).
 *
 * MIT License. Copyright (c) Chiptune Forge contributors.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to permit
 * persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
 * NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
 * USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Use: include your song's data with #incbin, naming it pce_song, then
 * include this file (it is meant to be #included, not compiled alone):
 *
 *     #incbin(pce_song, "song.bin");
 *     #include "pce_player.c"
 *
 * For sound effects, also include the sound data as pce_sfx and define
 * PCE_SFX before including this file. Then call pce_start() once, and
 * pce_frame() once per frame, after vsync(). pce_sfx_play(n) plays sound
 * effect n on channel 5, which the music gets back when the sound ends.
 *
 * Data format (written by Chiptune Forge, all 16-bit values little-endian,
 * offsets from the start of the data):
 *   0  "PCE" (or "PCS" for sound effects), version 1
 *   4  number of streams (6 channels for a song, sounds for effects)
 *   5  number of waveforms
 *   6  offset of the waveforms (32 bytes each, 0 to 31)
 *   8  offset of the instruments (8 bytes each: waveform, flags (1: noise),
 *      then the volume, arpeggio and pitch envelope offsets, 0 for none)
 *   10 offset of the arpeggio table (an envelope offset per arpeggio)
 *   12 the streams' offsets, then (songs only) their loop offsets, 0 for
 *      none, and each channel's balance (left volume in the high nibble,
 *      right in the low)
 * An envelope is its length, its loop point (255 for none) and its values
 * (signed for arpeggios and pitch). A stream is a list of commands:
 *   0-127 n, f    play note n (or noise frequency n) for f frames
 *   128-191       set the instrument (0 to 63) for the next notes
 *   192 v         set the volume (0 to 15) for the next notes
 *   193 a         set the arpeggio (255 for none) for the next notes
 *   194 f         silence for f frames
 *   195 f         hold the current note for f more frames
 *   254           jump to the stream's loop offset
 *   255           end of the stream
 */

#define PCE_CHANNELS 7
#define PCE_SFX_CHANNEL 6
#define PCE_SFX_VOICE 4

/* The 12-bit frequency divider for each MIDI note. */
const int pce_period[] = {
	PCE_PERIOD_TABLE
};

/* Channel volume (0 to 31) for each level (0 to 15, 2 dB steps). */
const unsigned char pce_volume[] = {
	PCE_VOLUME_TABLE
};

unsigned char pce_playing;
unsigned char pce_c;
unsigned int pce_pos[PCE_CHANNELS];
unsigned char pce_wait[PCE_CHANNELS];
unsigned char pce_ended[PCE_CHANNELS];
unsigned char pce_note[PCE_CHANNELS];
unsigned char pce_inst[PCE_CHANNELS];
unsigned char pce_vol[PCE_CHANNELS];
unsigned char pce_arp[PCE_CHANNELS];
unsigned char pce_env_vol[PCE_CHANNELS];
unsigned char pce_env_arp[PCE_CHANNELS];
unsigned char pce_env_pitch[PCE_CHANNELS];
unsigned char pce_arp_pos[PCE_CHANNELS];
unsigned char pce_loaded[6];
unsigned int pce_inst_at;
unsigned int pce_env_at;
unsigned int pce_word;
int pce_value;

/* A byte of the current channel's data: the sound effects for the sound
   effect channel, the song for the others. */
unsigned char pce_byte(unsigned int offset)
{
#ifdef PCE_SFX
	if (pce_c == PCE_SFX_CHANNEL)
		return farpeek(pce_sfx + offset);
#endif
	return farpeek(pce_song + offset);
}

unsigned int pce_word_at(unsigned int offset)
{
	pce_word = pce_byte(offset + 1);
	pce_word = (pce_word << 8) | pce_byte(offset);
	return pce_word;
}

/* An envelope's value at a position (in pce_value), or the default. */
void pce_env_value(unsigned int env, unsigned char at, int fallback)
{
	unsigned char length;
	if (env == 0) {
		pce_value = fallback;
		return;
	}
	length = pce_byte(env);
	if (length == 0) {
		pce_value = fallback;
		return;
	}
	if (at >= length)
		at = length - 1;
	pce_value = pce_byte(env + 2 + at);
}

/* The next position in an envelope. */
unsigned char pce_env_next(unsigned int env, unsigned char at)
{
	unsigned char length;
	unsigned char loop;
	if (env == 0)
		return 0;
	length = pce_byte(env);
	if (length == 0)
		return 0;
	loop = pce_byte(env + 1);
	++at;
	if (at >= length) {
		if (loop < length)
			return loop;
		return length - 1;
	}
	return at;
}

void pce_signed(void)
{
	if (pce_value >= 128)
		pce_value -= 256;
}

/* Starts stream n on channel pce_c. */
void pce_begin(unsigned int offset)
{
	pce_pos[pce_c] = offset;
	pce_wait[pce_c] = 0;
	pce_ended[pce_c] = 0;
	pce_note[pce_c] = 0;
	pce_inst[pce_c] = 255;
	pce_vol[pce_c] = 15;
	pce_arp[pce_c] = 255;
	pce_env_vol[pce_c] = 0;
	pce_env_arp[pce_c] = 0;
	pce_env_pitch[pce_c] = 0;
	pce_arp_pos[pce_c] = 0;
}

void pce_start(void)
{
	unsigned char c;
	poke(0x0801, 0xFF);
	for (c = 0; c < 6; ++c) {
		pce_c = c;
		poke(0x0800, c);
		poke(0x0804, 0);
		poke(0x0805, pce_byte(36 + c));
		pce_loaded[c] = 255;
		pce_begin(pce_word_at(12 + c * 2));
	}
#ifdef PCE_SFX
	pce_ended[PCE_SFX_CHANNEL] = 1;
#endif
	pce_playing = 1;
}

/* Plays sound effect n. */
void pce_sfx_play(unsigned char n)
{
#ifdef PCE_SFX
	pce_c = PCE_SFX_CHANNEL;
	pce_begin(pce_word_at(12 + n * 2));
#endif
}

/* Reads the current channel's commands up to its next note, silence or
   hold. */
void pce_read(void)
{
	unsigned char b;
	unsigned int pos;
	if (pce_ended[pce_c] || pce_wait[pce_c])
		return;
	pos = pce_pos[pce_c];
	for (;;) {
		b = pce_byte(pos);
		++pos;
		if (b < 128) {
			pce_note[pce_c] = b;
			pce_wait[pce_c] = pce_byte(pos);
			++pos;
			pce_env_vol[pce_c] = 0;
			pce_env_arp[pce_c] = 0;
			pce_env_pitch[pce_c] = 0;
			pce_arp_pos[pce_c] = 0;
			break;
		}
		if (b < 192) {
			pce_inst[pce_c] = b & 63;
		} else if (b == 192) {
			pce_vol[pce_c] = pce_byte(pos);
			++pos;
		} else if (b == 193) {
			pce_arp[pce_c] = pce_byte(pos);
			++pos;
		} else if (b == 194) {
			pce_note[pce_c] = 0;
			pce_wait[pce_c] = pce_byte(pos);
			++pos;
			break;
		} else if (b == 195) {
			pce_wait[pce_c] = pce_byte(pos);
			++pos;
			break;
		} else if (b == 254) {
			pos = pce_word_at(24 + pce_c * 2);
		} else {
			pce_note[pce_c] = 0;
			pce_ended[pce_c] = 1;
			break;
		}
	}
	pce_pos[pce_c] = pos;
}

/* Writes the current channel's registers on PSG channel voice. */
void pce_output(unsigned char voice)
{
	unsigned char wave;
	unsigned char flags;
	unsigned char i;
	unsigned char level;
	int note;
	int period;
	int step;
	unsigned int at;
	poke(0x0800, voice);
	if (pce_note[pce_c] == 0) {
		poke(0x0804, 0x80);
		return;
	}
	pce_inst_at = pce_word_at(8) + pce_inst[pce_c] * 8;
	wave = pce_byte(pce_inst_at);
	flags = pce_byte(pce_inst_at + 1);
	/* Sound effect waveforms are told apart from the song's. */
	i = wave;
	if (pce_c == PCE_SFX_CHANNEL)
		i = wave | 128;
	if (!(flags & 1) && pce_loaded[voice] != i) {
		poke(0x0804, 0x40);
		poke(0x0804, 0);
		at = pce_word_at(6) + wave * 32;
		for (wave = 0; wave < 32; ++wave)
			poke(0x0806, pce_byte(at + wave));
		pce_loaded[voice] = i;
	}
	/* The arpeggio: the note's, else the instrument's envelope. */
	if (pce_arp[pce_c] != 255) {
		pce_env_at = pce_word_at(pce_word_at(10) + pce_arp[pce_c] * 2);
		pce_env_value(pce_env_at, pce_arp_pos[pce_c], 0);
	} else {
		pce_env_value(pce_word_at(pce_inst_at + 4), pce_env_arp[pce_c], 0);
	}
	pce_signed();
	note = pce_note[pce_c] + pce_value;
	if (flags & 1) {
		if (note < 0)
			note = 0;
		if (note > 31)
			note = 31;
		poke(0x0807, 0x80 | note);
	} else {
		if (voice >= 4)
			poke(0x0807, 0);
		if (note < 0)
			note = 0;
		if (note > 127)
			note = 127;
		period = pce_period[note];
		pce_env_value(pce_word_at(pce_inst_at + 6), pce_env_pitch[pce_c], 0);
		pce_signed();
		if (pce_value != 0) {
			if (note > 126)
				note = 126;
			step = pce_period[note] - pce_period[note + 1];
			if (pce_value > 0)
				period -= (step * pce_value) >> 4;
			else
				period += (step * -pce_value) >> 4;
		}
		if (period < 1)
			period = 1;
		if (period > 4095)
			period = 4095;
		poke(0x0802, period & 0xFF);
		poke(0x0803, period >> 8);
	}
	pce_env_value(pce_word_at(pce_inst_at + 2), pce_env_vol[pce_c], 15);
	level = 0;
	if (pce_vol[pce_c] != 0 && pce_value != 0 && pce_vol[pce_c] + pce_value > 15)
		level = pce_vol[pce_c] + pce_value - 15;
	poke(0x0804, 0x80 | pce_volume[level]);
}

/* Moves the current channel's envelopes on a frame. */
void pce_advance(void)
{
	if (pce_inst[pce_c] < 64) {
		pce_inst_at = pce_word_at(8) + pce_inst[pce_c] * 8;
		pce_env_vol[pce_c] = pce_env_next(pce_word_at(pce_inst_at + 2), pce_env_vol[pce_c]);
		pce_env_arp[pce_c] = pce_env_next(pce_word_at(pce_inst_at + 4), pce_env_arp[pce_c]);
		pce_env_pitch[pce_c] = pce_env_next(pce_word_at(pce_inst_at + 6), pce_env_pitch[pce_c]);
	}
	if (pce_arp[pce_c] != 255)
		pce_arp_pos[pce_c] = pce_env_next(pce_word_at(pce_word_at(10) + pce_arp[pce_c] * 2), pce_arp_pos[pce_c]);
	if (pce_wait[pce_c])
		--pce_wait[pce_c];
}

/* Runs one frame of music and sound effects. Call once per frame. */
void pce_frame(void)
{
	unsigned char sfx;
	if (!pce_playing)
		return;
	sfx = 0;
#ifdef PCE_SFX
	pce_c = PCE_SFX_CHANNEL;
	if (!pce_ended[pce_c]) {
		pce_read();
		pce_output(PCE_SFX_VOICE);
		pce_advance();
		sfx = !pce_ended[pce_c];
	}
#endif
	for (pce_c = 0; pce_c < 6; ++pce_c) {
		pce_read();
		if (pce_c != PCE_SFX_VOICE || !sfx)
			pce_output(pce_c);
		pce_advance();
	}
}
