extends SceneTree
## Makes a community pack from vibes, styles and SFX presets saved as .tres
## files (tune them in the Godot editor's inspector, then pack them):
##   godot --headless --path . -s tools/make_pack.gd -- in_dir out.chippack "Pack name" ["Author"] ["Licence"]
## Every .tres file in in_dir that holds a Vibe, Style or SfxPreset goes in.
## The pack is checked as the app checks it before it is written.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: make_pack.gd -- in_dir out.chippack \"Pack name\" [\"Author\"] [\"Licence\"]")
		quit(2)
		return
	var resources: Array = []
	var files := Array(DirAccess.get_files_at(args[0]))
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var res := load(args[0].path_join(file))
		if res is Vibe or res is Style or res is SfxPreset:
			resources.append(res)
	var info := {"name": args[2]}
	if args.size() > 3:
		info["author"] = args[3]
	if args.size() > 4:
		info["license"] = args[4]
	var text := ChipPack.write(info, resources)
	var catalog := Catalog.new()
	catalog.load_all()
	var parsed := ChipPack.parse(text, catalog)
	if parsed.has("error"):
		printerr(parsed["error"])
		quit(1)
		return
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	if out == null:
		printerr("cannot write %s" % args[1])
		quit(1)
		return
	out.store_string(text)
	out.close()
	print("wrote %s: %s" % [args[1], (parsed["pack"] as ChipPack).summary()])
	quit(0)
