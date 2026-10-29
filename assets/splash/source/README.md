# Boot splash source

`boot_splash.svg` is the source for `../boot_splash.png`, the image Godot shows
while the app loads (see `application/boot_splash/*` in `project.godot`).

The text uses Space Grotesk and JetBrains Mono from `assets/fonts`, so install
those fonts before rendering. Render it at 1024×1024, for example:

    rsvg-convert -w 1024 -h 1024 boot_splash.svg -o ../boot_splash.png

The outer background (`#0F1014`) must match `application/boot_splash/bg_color`
so the image blends into the screen at any aspect ratio. To rename the app,
edit the wordmark `<text>` element.
