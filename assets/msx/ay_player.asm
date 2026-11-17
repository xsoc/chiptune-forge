; ay_player.asm: Chiptune Forge's music and sound effect player for the
; AY-3-8910 on the MSX and the ZX Spectrum 128 (Z80, Pasmo syntax).
;
; MIT License. Copyright (c) Chiptune Forge contributors.
;
; Permission is hereby granted, free of charge, to any person obtaining a
; copy of this software and associated documentation files (the
; "Software"), to deal in the Software without restriction, including
; without limitation the rights to use, copy, modify, merge, publish,
; distribute, sublicense, and/or sell copies of the Software, and to permit
; persons to whom the Software is furnished to do so, subject to the
; following conditions:
;
; The above copyright notice and this permission notice shall be included
; in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
; NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
; DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
; OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
; USE OR OTHER DEALINGS IN THE SOFTWARE.
;
; Use: before including this file, define AY_MSX or AY_ZX as 1 (the other
; as 0) and AY_RAM as the address of 64 bytes of RAM for the player.
;
;     ld hl,song          ; your song data (song_msx.bin or song_zx.bin)
;     call ay_init
;     ld hl,sounds        ; optional: your sound effects (sfx_msx.bin ...)
;     call ay_sfx_init
; loop:
;     ei
;     halt                ; wait for the frame interrupt
;     call ay_interrupt   ; or ay_frame, which never skips a frame
;     jr loop
;
; ay_sfx_play plays sound effect A on channel B over the music, which gets
; the channel back when the sound ends. ay_stop silences everything.
;
; The music runs at 50 frames a second. On a 60 Hz MSX, ay_interrupt skips
; every sixth interrupt so it plays at the right speed. Call ay_frame
; yourself if you time the frames some other way.
;
; Data format (written by Chiptune Forge; 16-bit values little-endian,
; offsets from the start of the data):
;   song:   0 "AYF", version 1;  4 loop offset (0: no loop);  6 the stream
;   sounds: 0 "AYS", version 1;  4 number of sounds;  5 their offsets
; A stream is a list of commands, one frame after another:
;   0-10 v           set register 0-10 to v
;   128-191          end of this frame, then wait 0-63 more frames
;   192 o, l         play the l bytes of stream at offset o, then go on
;   254              jump to the loop offset
;   255              end
; The first frame, and the frame at the loop point, set every register.

; Offsets in a stream's state.
AY_POS		equ 0
AY_WAIT		equ 2
AY_RET		equ 3
AY_END		equ 5
AY_BASE		equ 7
AY_LOOP		equ 9
AY_ON		equ 11
AY_REGS		equ 12
AY_STATE	equ 23

ay_music	equ AY_RAM
ay_sfx		equ AY_RAM + AY_STATE
ay_out		equ AY_RAM + AY_STATE * 2
ay_sfx_table	equ ay_out + 11
ay_skip		equ ay_sfx_table + 2
ay_count	equ ay_skip + 1

; ay_init: start the song at HL.
ay_init:
	push hl
	ld ix,ay_music
	call ay_clear
	pop hl
	ld (ay_music + AY_BASE),hl
	ld de,6
	add hl,de
	ld (ay_music + AY_POS),hl
	ld hl,(ay_music + AY_BASE)
	ld de,4
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(ay_music + AY_BASE)
	add hl,de
	ld (ay_music + AY_LOOP),hl
	ld a,1
	ld (ay_music + AY_ON),a
	ld ix,ay_sfx
	call ay_clear
	xor a
	ld (ay_count),a
	ld (ay_skip),a
	if AY_MSX
	; MSX BIOS: bit 7 of $002B is clear on 60 Hz machines.
	ld a,($002B)
	cpl
	and $80
	ld (ay_skip),a
	endif
	jp ay_frame

; ay_sfx_init: use the sound effects at HL.
ay_sfx_init:
	ld (ay_sfx_table),hl
	ret

; ay_sfx_play: play sound effect A.
ay_sfx_play:
	push af
	ld ix,ay_sfx
	call ay_clear
	pop af
	ld hl,(ay_sfx_table)
	ld (ay_sfx + AY_BASE),hl
	add a,a
	add a,5
	ld e,a
	ld d,0
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(ay_sfx_table)
	add hl,de
	ld (ay_sfx + AY_POS),hl
	ld a,1
	ld (ay_sfx + AY_ON),a
	ret

; ay_stop: silence the music and sound effects.
ay_stop:
	xor a
	ld (ay_music + AY_ON),a
	ld (ay_sfx + AY_ON),a
	jp ay_frame

; ay_interrupt: ay_frame, skipping every sixth call on a 60 Hz MSX.
ay_interrupt:
	ld a,(ay_skip)
	or a
	jr z,ay_frame
	ld a,(ay_count)
	inc a
	cp 6
	jr nz,ay_int_play
	xor a
	ld (ay_count),a
	ret
ay_int_play:
	ld (ay_count),a
	; fall through

; ay_frame: play one frame.
ay_frame:
	ld ix,ay_music
	call ay_step
	ld a,(ay_music + AY_ON)
	or a
	jr nz,ay_music_on
	ld (ay_music + AY_REGS + 8),a
	ld (ay_music + AY_REGS + 9),a
	ld (ay_music + AY_REGS + 10),a
ay_music_on:
	ld hl,ay_music + AY_REGS
	ld de,ay_out
	ld bc,11
	ldir
	ld ix,ay_sfx
	call ay_step
	ld a,(ay_sfx + AY_ON)
	or a
	jr z,ay_write
	; The sound owns channel B: its period, volume and mixer bits.
	ld a,(ay_sfx + AY_REGS + 2)
	ld (ay_out + 2),a
	ld a,(ay_sfx + AY_REGS + 3)
	ld (ay_out + 3),a
	ld a,(ay_sfx + AY_REGS + 9)
	ld (ay_out + 9),a
	ld a,(ay_sfx + AY_REGS + 7)
	and $12
	ld b,a
	ld a,(ay_out + 7)
	and $ED
	or b
	ld (ay_out + 7),a
	; And the noise period, if it uses noise.
	bit 4,b
	jr nz,ay_write
	ld a,(ay_sfx + AY_REGS + 6)
	ld (ay_out + 6),a
ay_write:
	if AY_MSX
	; Keep the MSX's I/O port A an input and port B an output.
	ld a,(ay_out + 7)
	and $3F
	or $80
	ld (ay_out + 7),a
	endif
	ld hl,ay_out
	xor a
ay_write_reg:
	ld e,(hl)
	inc hl
	if AY_MSX
	out ($A0),a
	ld d,a
	ld a,e
	out ($A1),a
	ld a,d
	endif
	if AY_ZX
	ld bc,$FFFD
	out (c),a
	ld b,$BF
	out (c),e
	endif
	inc a
	cp 11
	jr nz,ay_write_reg
	ret

; ay_clear: reset the stream state at IX (stopped, every register 0 and
; the mixer all off).
ay_clear:
	push ix
	pop hl
	ld b,AY_STATE
	xor a
ay_clear_byte:
	ld (hl),a
	inc hl
	djnz ay_clear_byte
	ld (ix + AY_REGS + 7),$3F
	ret

; ay_step: run one frame of the stream whose state is at IX.
ay_step:
	ld a,(ix + AY_ON)
	or a
	ret z
	ld a,(ix + AY_WAIT)
	or a
	jr z,ay_step_read
	dec (ix + AY_WAIT)
	ret
ay_step_read:
	ld l,(ix + AY_POS)
	ld h,(ix + AY_POS + 1)
ay_next:
	; At the end of a called stretch, go back to where it was called.
	ld a,(ix + AY_RET + 1)
	or a
	jr z,ay_op
	ld a,l
	cp (ix + AY_END)
	jr nz,ay_op
	ld a,h
	cp (ix + AY_END + 1)
	jr nz,ay_op
	ld l,(ix + AY_RET)
	ld h,(ix + AY_RET + 1)
	ld (ix + AY_RET + 1),0
ay_op:
	ld a,(hl)
	inc hl
	cp $80
	jr nc,ay_command
	; Register A = the next byte.
	push ix
	pop de
	add a,AY_REGS
	add a,e
	ld e,a
	jr nc,ay_reg_nc
	inc d
ay_reg_nc:
	ld a,(hl)
	inc hl
	ld (de),a
	jr ay_next
ay_command:
	cp $C0
	jr nc,ay_special
	and $3F
	ld (ix + AY_WAIT),a
	ld (ix + AY_POS),l
	ld (ix + AY_POS + 1),h
	ret
ay_special:
	jr nz,ay_not_call
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	ld (ix + AY_RET),l
	ld (ix + AY_RET + 1),h
	ld l,(ix + AY_BASE)
	ld h,(ix + AY_BASE + 1)
	add hl,de
	push hl
	add hl,bc
	ld (ix + AY_END),l
	ld (ix + AY_END + 1),h
	pop hl
	jr ay_next
ay_not_call:
	cp $FE
	jr nz,ay_stream_end
	ld l,(ix + AY_LOOP)
	ld h,(ix + AY_LOOP + 1)
	jr ay_next
ay_stream_end:
	ld (ix + AY_ON),0
	ret
