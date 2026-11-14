# FamiStudio sound engine (vendored)

The NES sound engine used by Chiptune Forge's NES exports, from FamiStudio
4.5.4 (https://github.com/BleuBleu/FamiStudio, tag `4.5.4`, commit
07b8c22c6c84e568ee405301737056fd53998ca5): `SoundEngine/famistudio_ca65.s`
`SoundEngine/famistudio_cc65.h` and the 2A03 note tables the engine
`.incbin`s (`SoundEngine/NoteTables/famistudio_note_table*_lsb/msb.bin`),
copied unchanged. FamiStudio is MIT
licensed (`LICENSE.txt`); the engine file carries its own permissive notice.

`scripts/targets/nes/famistudio_asm_writer.gd` writes music data in the
format this engine version reads. The format changes between FamiStudio
versions, so update the two together and check the CI `nes` job, which
compares the writer's output with FamiStudio's own export.
