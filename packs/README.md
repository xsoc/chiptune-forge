# Community packs

A pack adds vibes, styles and sound effect presets to Chiptune Forge. It is
one JSON file ending in `.chippack`. Packs hold only settings (numbers, text
and tables), never code, so a pack from anyone is safe to add.

## Adding a pack

Open **Library**, then press **Add a pack** under Community packs and pick
the `.chippack` file. Its vibes, styles and sounds show up in the pickers
straight away, in their groups after the built-in ones, and stay there next
time you open the app. To take a pack out again, press the bin by its name.

Songs remember the vibes and style they were made with by id. Keep the pack
installed to make a song again from its seed. A song you exported already has
all of its notes and needs no pack.

## Packs in this folder

| Pack | What it adds | Licence |
|---|---|---|
| [Seasons](seasons.chippack) | 4 seasonal vibes, a harvest-dance style, 2 weather sounds | CC0-1.0 |

To share a pack, open a pull request that adds it here with a line in this
table. The tests load every pack in this folder, so CI tells you if
something in it is wrong. Please license packs under CC0-1.0 or another
licence that lets anyone use the music they make with them.

## Making a pack

The quickest way is to copy [seasons.chippack](seasons.chippack) and change
it. The file looks like this:

```json
{
	"format": "chiptune-forge-pack",
	"version": 1,
	"name": "My pack",
	"author": "Your name or handle",
	"license": "CC0-1.0",
	"description": "What the pack is for.",
	"vibes": [ { "id": "neon_rain", "group": "Places", "tempo_min": 90, "tempo_max": 120 } ],
	"styles": [],
	"sfx_presets": []
}
```

- `format`, `version` and `name` are required. `author`, `license`,
  `description` and `url` are shown in the app.
- `vibes`, `styles` and `sfx_presets` are lists. Each item needs an `id` of
  lower-case letters, digits and underscores, which no built-in preset or
  other pack uses, and a `group` from the app's tabs (listed below).
- Every other property is optional and keeps its default when left out. The
  properties are the ones in
  [vibe.gd](../resources/types/vibe.gd), [style.gd](../resources/types/style.gd)
  and [sfx_preset.gd](../resources/types/sfx_preset.gd), and the
  built-in presets in [resources/](../resources) show what values they take.
- Names inside tables and text properties (modes, progression families,
  drum patterns, bass patterns, waves, sound parameters) must be ones the
  built-in presets use. The app says which name it does not know.

You can also tune presets in the Godot editor, where the inspector has a
slider for every property. Save them as `.tres` files in a folder, then pack
the folder:

```
godot --headless --path . -s tools/make_pack.gd -- my_presets/ my_pack.chippack "My pack" "Your name" CC0-1.0
```

### Groups

- Vibes: Bright and happy, Energetic, Calm and warm, Sad and reflective,
  Dark and tense, Scary and unsettling, Weird and trippy, Epic and grand,
  Mysterious and wondrous, Places, Game moments.
- Styles: Rock and metal, Electronic, Dance and club, Pop, soul and hip hop,
  Jazz and lounge, Orchestral and film, World and folk, Chill and ambient,
  Game genres.
- Sound presets: UI and menus, Combat, Damage and health, Pickups and
  rewards, Power, Movement, Game flow, Magic, World, Machines and sci-fi,
  Creatures and voices, Musical stingers.
