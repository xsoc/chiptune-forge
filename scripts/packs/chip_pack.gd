class_name ChipPack
extends RefCounted
## A community pack: vibes, styles and sound effect presets in one JSON file
## (.chippack), which anyone can make and share. See docs/packs.md.
##
## Each item lists the properties of a [Vibe], [Style] or [SfxPreset]; any
## property left out keeps its default. Packs only hold numbers, text and
## tables, never code, so a pack from anyone is safe to load.

const FORMAT := "chiptune-forge-pack"
const VERSION := 1
const EXTENSION := "chippack"
const KINDS := {"vibes": "Vibe", "styles": "Style", "sfx_presets": "SfxPreset"}
const MAX_BYTES := 1 << 20
const MAX_ITEMS := 500

var name := ""
var author := ""
var license := ""
var description := ""
var url := ""
## Loaded resources by kind ("vibes", "styles", "sfx_presets"): Array of Resource.
var items := {"vibes": [], "styles": [], "sfx_presets": []}
## The file's text, as installed.
var source := ""


func count() -> int:
	return items["vibes"].size() + items["styles"].size() + items["sfx_presets"].size()


## A one-line summary, such as "3 vibes, 1 style".
func summary() -> String:
	var parts := PackedStringArray()
	for kind in [["vibes", "vibe"], ["styles", "style"], ["sfx_presets", "sound"]]:
		var n: int = items[kind[0]].size()
		if n > 0:
			parts.append("%d %s%s" % [n, kind[1], "" if n == 1 else "s"])
	return ", ".join(parts)


## A safe file name for the pack, from its name.
func file_name() -> String:
	var slug := ""
	for c in name.to_lower():
		slug += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	slug = slug.trim_prefix("-").trim_suffix("-")
	return (slug if slug != "" else "pack") + "." + EXTENSION


## Reads a pack. Returns {"pack": ChipPack} or {"error": String}. Items are
## checked against [param catalog]'s groups; ids must not clash with it.
static func parse(text: String, catalog: Catalog = null) -> Dictionary:
	if text.length() > MAX_BYTES:
		return {"error": "The pack is larger than 1 MB."}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"error": "This is not a pack: %s on line %d." % [json.get_error_message(), json.get_error_line()]}
	var data: Variant = json.data
	if not data is Dictionary or data.get("format") != FORMAT:
		return {"error": "This is not a Chiptune Forge pack (its format should be \"%s\")." % FORMAT}
	if int(data.get("version", 0)) > VERSION:
		return {"error": "This pack needs a newer Chiptune Forge."}
	var pack := ChipPack.new()
	pack.name = str(data.get("name", "")).strip_edges()
	if pack.name == "":
		return {"error": "The pack has no name."}
	pack.author = str(data.get("author", ""))
	pack.license = str(data.get("license", ""))
	pack.description = str(data.get("description", ""))
	pack.url = str(data.get("url", ""))
	pack.source = text
	var seen := {}
	var total := 0
	for kind in KINDS:
		var list: Variant = data.get(kind, [])
		if not list is Array:
			return {"error": "\"%s\" should be a list." % kind}
		total += list.size()
		if total > MAX_ITEMS:
			return {"error": "The pack has more than %d items." % MAX_ITEMS}
		for entry in list:
			var made := _make(kind, entry, catalog)
			if made.has("error"):
				return made
			var res: Resource = made["item"]
			var key := "%s/%s" % [kind, res.id]
			if seen.has(key):
				return {"error": "The pack has two %s called \"%s\"." % [kind.replace("_", " "), res.id]}
			seen[key] = true
			pack.items[kind].append(res)
	if pack.count() == 0:
		return {"error": "The pack is empty."}
	return {"pack": pack}


static func _make(kind: String, entry: Variant, catalog: Catalog) -> Dictionary:
	if not entry is Dictionary:
		return {"error": "Each of the %s should be a table of properties." % kind.replace("_", " ")}
	var res: Resource
	match kind:
		"vibes":
			res = Vibe.new()
		"styles":
			res = Style.new()
		_:
			res = SfxPreset.new()
	var id := str(entry.get("id", ""))
	var label := "\"%s\"" % id if id != "" else "an item in %s" % kind
	if not _valid_id(id):
		return {"error": "%s needs an id of lower-case letters, digits and underscores." % label.capitalize()}
	var props := {}
	for p in res.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
			props[p["name"]] = p
	for key in entry:
		if not props.has(key):
			return {"error": "%s has a property Chiptune Forge does not know: \"%s\"." % [label, key]}
		var value: Variant = _convert(entry[key], res.get(key))
		if value == null:
			return {"error": "%s: \"%s\" has the wrong type." % [label, key]}
		res.set(key, value)
	if res.display_name == "":
		res.display_name = id.capitalize()
	if catalog != null:
		var groups: PackedStringArray = {"vibes": Catalog.VIBE_GROUPS, "styles": Catalog.STYLE_GROUPS, "sfx_presets": Catalog.SFX_GROUPS}[kind]
		if not groups.has(res.group):
			return {"error": "%s: the group should be one of %s." % [label, ", ".join(groups)]}
		var built_in: Dictionary = catalog.get(kind)
		if built_in.has(id) and not built_in[id].has_meta("pack"):
			return {"error": "%s: Chiptune Forge already has %s with this id." % [label, "a vibe" if kind == "vibes" else ("a style" if kind == "styles" else "a sound")]}
		var unknown := _unknown_name(res, known_names(catalog, kind))
		if unknown != "":
			return {"error": "%s: %s" % [label, unknown]}
	return {"item": res}


## The names the built-in presets use, per property: the keys of each table
## (modes, progression families, bass patterns, sound parameters...) and the
## values of each text property (drum patterns, waves...). A pack may only
## use these, so the generator knows every name it meets.
static func known_names(catalog: Catalog, kind: String) -> Dictionary:
	var cache_key := "known_" + kind
	if catalog.has_meta(cache_key):
		return catalog.get_meta(cache_key)
	var names := {}
	for item in (catalog.get(kind) as Dictionary).values():
		if item.has_meta("pack"):
			continue
		for p in item.get_property_list():
			if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE):
				continue
			var key: String = p["name"]
			if key in ["id", "display_name", "group", "description"]:
				continue
			_collect(names, key, item.get(key))
	if kind == "styles":
		for family in DrumBook.PATTERNS:
			names.get_or_add("drum_pattern", {})[family] = true
		for form in SongGenerator.FORM_TEMPLATES:
			names.get_or_add("forms", {})[form] = true
	if kind == "vibes":
		for form in SongGenerator.FORM_TEMPLATES:
			names.get_or_add("form_hint", {})[form] = true
		names.get_or_add("form_hint", {})["jingle"] = true
	catalog.set_meta(cache_key, names)
	return names


static func _collect(names: Dictionary, key: String, value: Variant) -> void:
	var seen: Dictionary = names.get_or_add(key, {})
	if value is String:
		seen[value] = true
	elif value is PackedStringArray:
		for v in value:
			seen[v] = true
	elif value is Dictionary:
		for k in value:
			seen[k] = true
			if value[k] is String:
				_collect(names, key + "." + str(k), value[k])
	elif value is Array:
		for v in value:
			if v is String:
				seen[v] = true
			elif v is Dictionary:
				for k in v:
					if k == "name":
						continue
					seen[k] = true
					_collect(names, key + "." + str(k), v[k])


## A message for the first name the built-in presets never use, or "".
static func _unknown_name(res: Resource, names: Dictionary) -> String:
	for key in names:
		if key.contains("."):
			continue
		var value: Variant = res.get(key)
		var problem := _check_value(names, key, value)
		if problem != "":
			return problem
	return ""


static func _check_value(names: Dictionary, key: String, value: Variant) -> String:
	var seen: Dictionary = names.get(key, {})
	if value is String:
		if value != "" and not seen.has(value):
			return "\"%s\" is not a %s Chiptune Forge knows." % [value, key.get_slice(".", key.get_slice_count(".") - 1).replace("_", " ")]
	elif value is PackedStringArray:
		for v in value:
			if not seen.has(v):
				return "\"%s\" is not one of the %s Chiptune Forge knows." % [v, key.replace("_", " ")]
	elif value is Dictionary:
		for k in value:
			if not seen.has(k):
				return "\"%s\" in %s is not a name Chiptune Forge knows." % [k, key]
			var v: Variant = value[k]
			if v is String:
				var problem := _check_value(names, key + "." + str(k), v)
				if problem != "":
					return problem
			elif not (v is float or v is int or v is bool or (v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int)) or (v is Array and k == "waves")):
				return "%s: \"%s\" should be a number." % [key, k]
	elif value is Array:
		for v in value:
			if v is String:
				if not seen.has(v):
					return "\"%s\" is not one of the %s Chiptune Forge knows." % [v, key.replace("_", " ")]
				continue
			if not v is Dictionary:
				return "%s should hold tables." % key
			for k in v:
				if k == "name":
					continue
				if not seen.has(k):
					return "\"%s\" in %s is not a name Chiptune Forge knows." % [k, key]
				var problem := _check_value(names, key + "." + str(k), v[k])
				if problem != "":
					return problem
	return ""


static func _valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 48:
		return false
	for c in id:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## The JSON value as the type of [param current], or null when it does not
## fit.
static func _convert(value: Variant, current: Variant) -> Variant:
	match typeof(current):
		TYPE_STRING:
			return value if value is String else null
		TYPE_BOOL:
			return value if value is bool else null
		TYPE_INT:
			return int(value) if (value is float or value is int) else null
		TYPE_FLOAT:
			return float(value) if (value is float or value is int) else null
		TYPE_DICTIONARY:
			return _plain(value) if value is Dictionary else null
		TYPE_PACKED_STRING_ARRAY:
			if not value is Array:
				return null
			for v in value:
				if not v is String:
					return null
			return PackedStringArray(value)
		TYPE_ARRAY:
			if not value is Array:
				return null
			var out: Array[Dictionary] = []
			for v in value:
				if not v is Dictionary:
					return null
				out.append(_plain(v))
			return out
	return null


## JSON numbers come back as floats: keep whole numbers whole, as the
## presets' own files have them.
static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _plain(value[k])
		return out
	if value is Array:
		var out: Array = []
		for v in value:
			out.append(_plain(v))
		return out
	return value


## A pack from resources, as JSON text: for authors who tune presets in the
## Godot editor (see tools/make_pack.gd).
static func write(info: Dictionary, resources: Array) -> String:
	var data := {"format": FORMAT, "version": VERSION}
	for key in ["name", "author", "license", "description", "url"]:
		if info.has(key):
			data[key] = info[key]
	for kind in KINDS:
		data[kind] = []
	for res in resources:
		var kind := "vibes" if res is Vibe else ("styles" if res is Style else "sfx_presets")
		var entry := {}
		for p in res.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
				var v: Variant = res.get(p["name"])
				entry[p["name"]] = Array(v) if v is PackedStringArray else v
		data[kind].append(entry)
	for kind in KINDS:
		if data[kind].is_empty():
			data.erase(kind)
	return JSON.stringify(data, "\t", false) + "\n"
