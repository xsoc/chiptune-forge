; sid_player.s: Chiptune Forge's music and sound effect player for the
; Commodore 64's SID (6502, ca65 syntax). sid_player.bin is this file
; assembled at $1000:
;
;     ca65 sid_player.s -o sid_player.o
;     ld65 -C sid_player.cfg sid_player.o -o sid_player.bin
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
; Use (the jump table at $1000 is the usual one for SID music):
;   $1000  init: start the song whose address is at $100C/$100D
;   $1003  play: call once per frame (50 times a second, on a PAL machine)
;   $1006  sfx init: A/X = low/high address of your sound effects
;   $1009  sfx play: play sound effect A on voice 2, over the music, which
;          gets the voice back when the sound ends
; The player uses zero page $FB and $FC.
;
; Data format (written by Chiptune Forge; 16-bit values little-endian,
; offsets from the start of the data):
;   song:   0 "SIF", version 1;  4 loop offset (0: no loop);  6 the stream
;   sounds: 0 "SIS", version 1;  4 number of sounds;  5 their offsets
; A stream is a list of commands, one frame after another:
;   0-24 v           set SID register 0-24 to v
;   128-191          end of this frame, then wait 0-63 more frames
;   192 o, l         play the l bytes of stream at offset o, then go on
;   254              jump to the loop offset
;   255              end
; The first frame, and the frame at the loop point, set every register.

ptr = $fb
SID = $d400

.segment "CODE"

	jmp init
	jmp play
	jmp sfx_init
	jmp sfx_play
song:	.word 0

init:
	ldx #0
	jsr clear
	ldx #1
	jsr clear
	lda song
	sta base_lo
	sta ptr
	lda song + 1
	sta base_hi
	sta ptr + 1
	clc
	lda base_lo
	adc #6
	sta pos_lo
	lda base_hi
	adc #0
	sta pos_hi
	ldy #4
	lda (ptr),y
	clc
	adc base_lo
	sta loop_lo
	iny
	lda (ptr),y
	adc base_hi
	sta loop_hi
	lda #1
	sta on
	jmp play

sfx_init:
	sta table
	stx table + 1
	rts

sfx_play:
	pha
	ldx #1
	jsr clear
	pla
	asl
	clc
	adc #5
	tay
	lda table
	sta ptr
	sta base_lo + 1
	lda table + 1
	sta ptr + 1
	sta base_hi + 1
	lda (ptr),y
	clc
	adc base_lo + 1
	sta pos_lo + 1
	iny
	lda (ptr),y
	adc base_hi + 1
	sta pos_hi + 1
	lda #1
	sta on + 1
	rts

play:
	ldx #0
	jsr step
	lda on
	bne music_on
	; The song has ended: release every voice.
	lda regs + 4
	and #$fe
	sta regs + 4
	lda regs + 11
	and #$fe
	sta regs + 11
	lda regs + 18
	and #$fe
	sta regs + 18
music_on:
	ldy #24
copy:
	lda regs,y
	sta out,y
	dey
	bpl copy
	ldx #1
	jsr step
	lda on + 1
	beq write
	; The sound owns voice 2 (registers 7 to 13).
	ldy #6
copy_sfx:
	lda regs + 25 + 7,y
	sta out + 7,y
	dey
	bpl copy_sfx
write:
	ldy #24
write_reg:
	lda out,y
	sta SID,y
	dey
	bpl write_reg
	rts

; clear: reset stream X (stopped, every register 0).
clear:
	lda #0
	sta pos_lo,x
	sta pos_hi,x
	sta wait,x
	sta ret_lo,x
	sta ret_hi,x
	sta end_lo,x
	sta end_hi,x
	sta on,x
	ldy regoff,x
	lda #25
	sta tmp
	lda #0
clear_reg:
	sta regs,y
	iny
	dec tmp
	bne clear_reg
	rts

; step: run one frame of stream X.
step:
	lda on,x
	bne step_on
	rts
step_on:
	lda wait,x
	beq step_read
	dec wait,x
	rts
step_read:
	lda pos_lo,x
	sta ptr
	lda pos_hi,x
	sta ptr + 1
next:
	; At the end of a called stretch, go back to where it was called.
	lda ret_hi,x
	beq op
	lda ptr
	cmp end_lo,x
	bne op
	lda ptr + 1
	cmp end_hi,x
	bne op
	lda ret_lo,x
	sta ptr
	lda ret_hi,x
	sta ptr + 1
	lda #0
	sta ret_hi,x
op:
	ldy #0
	lda (ptr),y
	bmi command
	clc
	adc regoff,x
	sta tmp
	iny
	lda (ptr),y
	ldy tmp
	sta regs,y
	lda #2
	jsr advance
	jmp next
command:
	cmp #$c0
	bcs special
	and #$3f
	sta wait,x
	lda #1
	jsr advance
	lda ptr
	sta pos_lo,x
	lda ptr + 1
	sta pos_hi,x
	rts
special:
	bne not_call
	ldy #1
	lda (ptr),y
	clc
	adc base_lo,x
	sta tmp
	iny
	lda (ptr),y
	adc base_hi,x
	sta tmp + 1
	iny
	lda (ptr),y
	clc
	adc tmp
	sta end_lo,x
	iny
	lda (ptr),y
	adc tmp + 1
	sta end_hi,x
	lda #5
	jsr advance
	lda ptr
	sta ret_lo,x
	lda ptr + 1
	sta ret_hi,x
	lda tmp
	sta ptr
	lda tmp + 1
	sta ptr + 1
	jmp next
not_call:
	cmp #$fe
	bne stream_end
	lda loop_lo,x
	sta ptr
	lda loop_hi,x
	sta ptr + 1
	jmp next
stream_end:
	lda #0
	sta on,x
	rts

; advance: move ptr on by A bytes.
advance:
	clc
	adc ptr
	sta ptr
	bcc advance_done
	inc ptr + 1
advance_done:
	rts

; State: index 0 is the music, 1 the sound effect.
regoff:	.byte 0, 25
pos_lo:	.res 2
pos_hi:	.res 2
wait:	.res 2
ret_lo:	.res 2
ret_hi:	.res 2
end_lo:	.res 2
end_hi:	.res 2
base_lo: .res 2
base_hi: .res 2
loop_lo: .res 2
loop_hi: .res 2
on:	.res 2
tmp:	.res 2
table:	.res 2
regs:	.res 50
out:	.res 25
