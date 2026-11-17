class_name GbaWriter
extends RefCounted
## Writes Game Boy Advance exports for Maxmod (devkitPro): the song as an
## Impulse Tracker module with 8-bit samples, and a small devkitARM project
## (Makefile and main.c) that builds a ROM playing it, with sound effects as
## 8-bit WAVs in the same soundbank.


## The module, as mmutil takes it.
static func module_bytes(gba: GbaSong) -> PackedByteArray:
	return ItWriter.module_bytes(gba, true)


## A Makefile for devkitARM that builds the soundbank from audio/ with
## mmutil and links main.c with libgba and Maxmod.
static func makefile(rom: String) -> String:
	return "\n".join(PackedStringArray([
		"# Builds %s.gba with devkitPro's devkitARM, libgba and Maxmod." % rom,
		"# Install devkitPro's gba-dev group (https://devkitpro.org) and set DEVKITPRO.",
		"ifeq ($(strip $(DEVKITPRO)),)",
		"$(error \"Set DEVKITPRO to where devkitPro is installed\")",
		"endif",
		"DEVKITARM ?= $(DEVKITPRO)/devkitARM",
		"TOOLS := $(DEVKITPRO)/tools/bin",
		"CC := $(DEVKITARM)/bin/arm-none-eabi-gcc",
		"OBJCOPY := $(DEVKITARM)/bin/arm-none-eabi-objcopy",
		"LIBGBA := $(DEVKITPRO)/libgba",
		"ARCH := -mthumb -mthumb-interwork",
		"CFLAGS := -O2 -Wall $(ARCH) -mcpu=arm7tdmi -mtune=arm7tdmi -I$(LIBGBA)/include -Ibuild",
		"LDFLAGS := -specs=gba.specs $(ARCH) -L$(LIBGBA)/lib",
		"AUDIO := $(wildcard audio/*)",
		"",
		"%s.gba: build/%s.elf" % [rom, rom],
		"\t$(OBJCOPY) -O binary $< $@",
		"\t$(TOOLS)/gbafix $@",
		"",
		"build/%s.elf: build/main.o build/soundbank_bin.o" % rom,
		"\t$(CC) $(LDFLAGS) $^ -lmm -lgba -o $@",
		"",
		"build/soundbank.bin build/soundbank.h: $(AUDIO)",
		"\tmkdir -p build",
		"\t$(TOOLS)/mmutil $(AUDIO) -obuild/soundbank.bin -hbuild/soundbank.h",
		"",
		"build/soundbank_bin.o: build/soundbank.bin",
		"\tcd build && $(TOOLS)/bin2s -a 4 soundbank.bin > soundbank_bin.s",
		"\t$(CC) -x assembler-with-cpp -c build/soundbank_bin.s -o $@",
		"",
		"build/main.o: main.c build/soundbank.h",
		"\t$(CC) $(CFLAGS) -c main.c -o $@",
		"",
		"clean:",
		"\trm -rf build *.gba",
	])) + "\n"


## A minimal libgba program that plays the song in a loop (and, with sound
## effects, plays the next one every two seconds).
static func main_c(title: String, module: String, sfx_symbols: PackedStringArray = []) -> String:
	var lines := PackedStringArray([
		"// %s: plays the song with Maxmod on the Game Boy Advance." % title,
		"// Made with Chiptune Forge.",
		"#include <gba.h>",
		"#include <maxmod.h>",
		"",
		"#include \"soundbank.h\"",
		"",
		"extern const u8 soundbank_bin[];",
		"",
	])
	if not sfx_symbols.is_empty():
		lines.append("static const mm_word sounds[] = { %s };" % ", ".join(sfx_symbols))
		lines.append("")
	lines.append_array([
		"int main(void)",
		"{",
		"    irqInit();",
		"    irqSet(IRQ_VBLANK, mmVBlank);",
		"    irqEnable(IRQ_VBLANK);",
		"",
		"    // Eight channels: the song uses seven, the eighth is for sound effects.",
		"    mmInitDefault((mm_addr)soundbank_bin, 8);",
		"    mmStart(%s, MM_PLAY_LOOP);" % module,
	])
	if not sfx_symbols.is_empty():
		lines.append_array([
			"",
			"    int frames = 0;",
			"    int next = 0;",
		])
	lines.append_array([
		"    while (1)",
		"    {",
		"        VBlankIntrWait();",
		"        mmFrame();",
	])
	if not sfx_symbols.is_empty():
		lines.append_array([
			"        // Every two seconds, the next sound effect.",
			"        if (++frames >= 120)",
			"        {",
			"            frames = 0;",
			"            mmEffect(sounds[next]);",
			"            next = (next + 1) %% %d;" % sfx_symbols.size(),
			"        }",
		])
	lines.append_array(["    }", "}"])
	return "\n".join(lines) + "\n"


static func readme(rom: String, gba: GbaSong) -> String:
	var module := ItWriter.module_id(rom + ".it")
	return "\n".join(PackedStringArray([
		"%s: music for the Game Boy Advance, for Maxmod" % gba.title,
		"",
		"audio/%s.it is an Impulse Tracker module with 8-bit samples for Maxmod," % rom,
		"devkitPro's sound library, which mixes it into the GBA's Direct Sound",
		"channels. It uses seven channels; the eighth is left for sound effects.",
		"",
		"To build the example ROM, install devkitPro's gba-dev group, set DEVKITPRO,",
		"and run make here. It makes %s.gba, which plays the song." % rom,
		"",
		"In your own game, put the module in your audio/ folder (devkitPro's GBA",
		"template runs mmutil on it) and play it:",
		"",
		"  mmInitDefault((mm_addr)soundbank_bin, 8);",
		"  mmStart(%s, MM_PLAY_LOOP);" % module,
		"",
		"and call mmFrame() once per frame, with mmVBlank as the VBlank interrupt.",
	])) + "\n"
