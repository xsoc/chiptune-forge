class_name ProjectFile
extends RefCounted
## A .cforge project: everything needed to export a song or a sound kit
## again, for another target or in other formats. Every export holds one,
## and the command line's export command reads it.
##
## JSON: {format, version, kind: "song" or "kit", target, and for a song
## settings (the Generate screen's, with the seed) and song (the notes, so
## hand edits survive), or for a kit name and sounds (id to .chipsfx data)}.

const FORMAT := "chiptune-forge-project"
const VERSION := 1
const EXTENSION := "cforge"


static func for_song(song: ChipSong, settings: SongSettings, target: String, gameboy_options := {}) -> String:
	var data := {
		"format": FORMAT,
		"version": VERSION,
		"kind": "song",
		"target": target,
		"settings": settings.to_dict() if settings else {},
		"song": song.data,
	}
	if target == "gameboy" and not gameboy_options.is_empty():
		data["gameboy"] = gameboy_options
	if target == "pc" and gameboy_options.has("card"):
		data["card"] = str(gameboy_options["card"])
	return JSON.stringify(data, "\t", false) + "\n"


static func for_kit(kit_name: String, sounds: Dictionary, target: String, card := "") -> String:
	var list := {}
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		list[id] = (sounds[id] as ChipSfx).data
	var data := {
		"format": FORMAT,
		"version": VERSION,
		"kind": "kit",
		"target": target,
		"name": kit_name,
		"sounds": list,
	}
	if target == "pc" and card != "":
		data["card"] = card
	return JSON.stringify(data, "\t", false) + "\n"


## Reads a project, or a .chipsong, .chipsfx or .chipkit file. Returns
## {"kind": "song", "song", "settings", "target", "gameboy"} or
## {"kind": "kit", "name", "sounds", "target", "card"}, or {"error": String}.
## A PC project's sound card is under "card" in "gameboy" (songs) or in
## "card" (kits).
static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"error": "not a JSON object"}
	var data: Dictionary = parsed
	match str(data.get("format", "")):
		FORMAT:
			if int(data.get("version", 0)) > VERSION:
				return {"error": "made by a newer Chiptune Forge"}
			if data.get("kind") == "song":
				if not data.get("song") is Dictionary:
					return {"error": "the project has no song"}
				var problem := ChipSong.validate(data["song"])
				if problem != "":
					return {"error": problem}
				return {
					"kind": "song",
					"song": ChipSong.from_dict(data["song"]),
					"settings": SongSettings.from_dict(data.get("settings", {})),
					"target": str(data.get("target", "modern")),
					"gameboy": (data.get("gameboy", {}) as Dictionary).merged({"card": str(data["card"])}) if data.has("card") else data.get("gameboy", {}),
				}
			if data.get("kind") == "kit":
				var sounds := {}
				var list: Variant = data.get("sounds", {})
				if not list is Dictionary:
					return {"error": "sounds should be a table"}
				for id in list:
					if not list[id] is Dictionary:
						return {"error": "%s is not a sound" % id}
					var problem := ChipSfx.validate(list[id])
					if problem != "":
						return {"error": "%s: %s" % [id, problem]}
					sounds[str(id)] = ChipSfx.from_dict(list[id])
				return {"kind": "kit", "name": str(data.get("name", "kit")), "sounds": sounds, "target": str(data.get("target", "modern")), "card": str(data.get("card", ""))}
			return {"error": "kind should be song or kit"}
		ChipSong.FORMAT:
			var problem := ChipSong.validate(data)
			if problem != "":
				return {"error": problem}
			var song := ChipSong.from_dict(data)
			var meta: Dictionary = data.get("meta", {}) if data.get("meta") is Dictionary else {}
			var settings := SongSettings.from_dict(meta.get("settings", {}) if meta.get("settings") is Dictionary else {})
			return {"kind": "song", "song": song, "settings": settings, "target": "modern", "gameboy": {}}
		ChipSfx.FORMAT:
			var problem := ChipSfx.validate(data)
			if problem != "":
				return {"error": problem}
			var sfx := ChipSfx.from_dict(data)
			return {"kind": "kit", "name": sfx.get_sound_name(), "sounds": {ExportJob.sanitize(sfx.get_sound_name()): sfx}, "target": "modern"}
		ChipSfxKit.FORMAT:
			var kit := ChipSfxKit.from_dict(data)
			if kit == null:
				return {"error": "not a valid sound kit"}
			return {"kind": "kit", "name": kit.kit_name, "sounds": kit.sounds, "target": "modern"}
	return {"error": "not a Chiptune Forge project, song, sound or kit"}
