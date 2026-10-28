class_name Catalog
extends RefCounted
## Every vibe, style, SFX preset and chip profile, loaded from their folders.
##
## New presets need no code: drop a .tres file into the matching folder.

const VIBES_DIR := "res://resources/vibes"
const STYLES_DIR := "res://resources/styles"
const SFX_DIR := "res://resources/sfx_presets"
const CHIPS_DIR := "res://resources/chips"

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

static var _default: Catalog


## The shared catalog, loaded on first use.
static func get_default() -> Catalog:
	if _default == null:
		_default = Catalog.new()
		_default.load_all()
	return _default


func load_all() -> void:
	vibes = _load_dir(VIBES_DIR)
	styles = _load_dir(STYLES_DIR)
	sfx_presets = _load_dir(SFX_DIR)
	chips = _load_dir(CHIPS_DIR)


func get_vibe(id: String) -> Vibe:
	return vibes.get(id)


func get_style(id: String) -> Style:
	return styles.get(id)


func get_sfx_preset(id: String) -> SfxPreset:
	return sfx_presets.get(id)


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
