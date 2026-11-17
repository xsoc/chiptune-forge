# Chiptune Forge's command line, for CI and build servers. See docs/cli.md.
#   docker build -t chiptune-forge .
#   docker run --rm -v "$PWD:/work" chiptune-forge generate --vibe happy --seed 1 --out build/music
# Paths are relative to /work, so mount your project there.
FROM ubuntu:24.04

ARG GODOT_VERSION=4.5.1
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -sSLo /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& rm /tmp/godot.zip

COPY . /opt/chiptune-forge
RUN godot --headless --path /opt/chiptune-forge --import < /dev/null; \
	install -m 755 /opt/chiptune-forge/docker/entrypoint.sh /usr/local/bin/chiptune-forge \
	&& chmod -R a+rwX /opt/chiptune-forge

WORKDIR /work
ENTRYPOINT ["chiptune-forge"]
CMD ["help"]
