class_name Catalog
extends RefCounted
## Every vibe, style, SFX preset and chip profile, loaded from their folders.
##
## New presets need no code: drop a .tres file into the matching folder.
## Community packs ([ChipPack]) add more at run time; their items carry the
## pack's name as the "pack" meta.

const VIBES_DIR := "res://resources/vibes"
const STYLES_DIR := "res://resources/styles"
const SFX_DIR := "res://resources/sfx_presets"
const CHIPS_DIR := "res://resources/chips"
## Where installed packs live.
const PACKS_DIR := "user://packs"

## Group order for the picker tabs, as in the spec.
const VIBE_GROUPS: PackedStringArray = [
	"Bright and happy", "Energetic", "Calm and warm", "Sad and reflective",
	"Dark and tense", "Scary and unsettling", "Weird and trippy", "Epic and grand",
	"Mysterious and wondrous", "Places", "Game moments",
]
const STYLE_GROUPS: PackedStringArray = [
	"Rock and metal", "Electronic", "Dance and club", "Pop, soul and hip hop",
	"Jazz and lounge", "Orchestral and film", "World and folk", "Chill and ambient",
	"Game genres",
]
const SFX_GROUPS: PackedStringArray = [
	"UI and menus", "Combat", "Damage and health", "Pickups and rewards", "Power",
	"Movement", "Game flow", "Magic", "World", "Machines and sci-fi",
	"Creatures and voices", "Musical stingers",
]

var vibes: Dictionary = {}
var styles: Dictionary = {}
var sfx_presets: Dictionary = {}
var chips: Dictionary = {}
## Installed packs, in the order they were added.
var packs: Array[ChipPack] = []

static var _default: Catalog


## The shared catalog, loaded on first use.
static func get_default() -> Catalog:
	if _default == null:
		_default = Catalog.new()
		_default.load_all()
		_default.load_packs(PACKS_DIR)
	return _default


func load_all() -> void:
	vibes = _load_dir(VIBES_DIR)
	styles = _load_dir(STYLES_DIR)
	sfx_presets = _load_dir(SFX_DIR)
	chips = _load_dir(CHIPS_DIR)


## Adds every pack in a folder. Returns the errors, one per broken file.
func load_packs(dir: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return errors
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for file in files:
		if not file.ends_with("." + ChipPack.EXTENSION):
			continue
		var parsed := ChipPack.parse(FileAccess.get_file_as_string(dir.path_join(file)), self)
		var error: String = parsed.get("error", "")
		if error == "":
			error = add_pack(parsed["pack"])
		if error != "":
			errors.append("%s: %s" % [file, error])
	return errors


## Adds a pack's items, replacing an earlier version of the same pack.
## Returns an error when an id is taken by another pack.
func add_pack(pack: ChipPack) -> String:
	for kind in ChipPack.KINDS:
		var items: Dictionary = get(kind)
		for res in pack.items[kind]:
			if items.has(res.id):
				var owner: String = items[res.id].get_meta("pack", "")
				if owner == "":
					return "Chiptune Forge already has \"%s\"." % res.id
				if owner != pack.name:
					return "The pack \"%s\" already has \"%s\"." % [owner, res.id]
	remove_pack(pack.name)
	for kind in ChipPack.KINDS:
		var items: Dictionary = get(kind)
		var order := 100000 + packs.size() * 1000
		for res in pack.items[kind]:
			res.set_meta("pack", pack.name)
			res.set_meta("order", order)
			order += 1
			items[res.id] = res
	packs.append(pack)
	return ""


func remove_pack(pack_name: String) -> void:
	for kind in ChipPack.KINDS:
		var items: Dictionary = get(kind)
		for id in items.keys():
			if items[id].get_meta("pack", "") == pack_name:
				items.erase(id)
	for i in range(packs.size() - 1, -1, -1):
		if packs[i].name == pack_name:
			packs.remove_at(i)


func get_pack(pack_name: String) -> ChipPack:
	for pack in packs:
		if pack.name == pack_name:
			return pack
	return null


func get_vibe(id: String) -> Vibe:
	return vibes.get(id)


func get_style(id: String) -> Style:
	return styles.get(id)


func get_sfx_preset(id: String) -> SfxPreset:
	return sfx_presets.get(id)


## A gentle note when a vibe and a style pull in different directions, or ""
## when they suit each other.
static func combo_note(vibe: Vibe, style: Style) -> String:
	if vibe == null or style == null:
		return ""
	if vibe.tempo_max < style.tempo_min - 10 or vibe.tempo_min > style.tempo_max + 10:
		return "Unusual combo: %s and %s want different tempos, so they meet in the middle." % [vibe.display_name, style.display_name]
	if vibe.energy < 0.3 and style.drum_density > 0.75:
		return "Unusual combo: a calm vibe with a busy style. Try lowering Intensity."
	return ""


## "Surprise me": a vibe and style that suit each other, as [vibe id,
## style id]. The same [param rng] state gives the same pair.
func surprise_pair(rng: Pcg32) -> PackedStringArray:
	var vibe_ids := vibes.keys()
	var style_ids := styles.keys()
	vibe_ids.sort()
	style_ids.sort()
	for attempt in 64:
		var vibe: Vibe = vibes[rng.pick(vibe_ids)]
		var style: Style = styles[rng.pick(style_ids)]
		if combo_note(vibe, style) == "" and vibe.tempo_max >= style.tempo_min and vibe.tempo_min <= style.tempo_max:
			return PackedStringArray([vibe.id, style.id])
	return PackedStringArray([vibe_ids[0], style_ids[0]])


## Items of one group, in the order their files sort.
func in_group(items: Dictionary, group: String) -> Array:
	var out: Array = []
	for id in _sorted_ids(items):
		if items[id].group == group:
			out.append(items[id])
	return out


## Items whose name or group contains [param query], ignoring case.
func search(items: Dictionary, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for id in _sorted_ids(items):
		var item: Resource = items[id]
		if q == "" or item.display_name.to_lower().contains(q) or item.description.to_lower().contains(q):
			out.append(item)
	return out


func _sorted_ids(items: Dictionary) -> Array:
	var ids := items.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return items[a].get_meta("order", 0) < items[b].get_meta("order", 0))
	return ids


func _load_dir(path: String) -> Dictionary:
	var out := {}
	var files := ResourceLoader.list_directory(path)
	var names: Array = []
	for file in files:
		if file.ends_with(".tres") or file.ends_with(".res"):
			names.append(file)
	names.sort()
	var order := 0
	for file in names:
		var res := load(path.path_join(file))
		if res == null or not "id" in res:
			continue
		res.set_meta("order", order)
		order += 1
		out[res.id] = res
	return out
