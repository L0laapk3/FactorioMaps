# Running FactorioMaps in a container

Factorio only renders in the **full client** — the headless build cannot produce
screenshots at all. This image therefore runs the normal client against an Xvfb
display, with Mesa providing OpenGL. It works with or without a GPU.

## Quick start

```bash
cd docker
mkdir -p data/saves data/mods
cp /path/to/your.zip data/saves/
cp -r /path/to/mods/* data/mods/          # the mods the save was made with
export FACTORIO_USERNAME=... FACTORIO_TOKEN=...   # from your player-data.json
docker compose run --rm factoriomaps --no-update --all-surfaces --maxthreads 4 mymap your
```

The generated map lands in `data/script-output/FactorioMaps/mymap`. Serve that
directory with any static web server.

Everything after the image name is passed straight to `auto.py`, so all the
normal flags work (`--hd`, `--dayonly`, `--surface`, and so on).

## The factorio client

The client is not baked into the image. On first run it is downloaded into the
`factorio-client` volume using `FACTORIO_USERNAME` and `FACTORIO_TOKEN`, which
you can read out of your own `player-data.json` (`service-username` and
`service-token`). Pin a version with `FACTORIO_VERSION=2.1.14` if you need to
match a save exactly.

If you would rather not hand credentials to the container, extract a client
yourself and mount it read-write at `/factorio` instead.

## GPU

The compose file passes `/dev/dri` through and joins the `video` and `render`
groups, which gives hardware rendering on Intel and AMD. Check what you got:

```bash
docker compose run --rm factoriomaps shell glxinfo -B | grep "OpenGL renderer"
```

`Mesa Intel(R) ...` means hardware. `llvmpipe` means software rendering, which
works but is several times slower. Remove the `devices` and `group_add` blocks
to force software rendering, or set `LIBGL_ALWAYS_SOFTWARE=1`.

NVIDIA needs the nvidia-container-toolkit and `--gpus all` instead of the
`/dev/dri` passthrough.

## Watching it work

Set `ENABLE_VNC=1` and open `http://<host>:6080/vnc.html`. Useful the first time,
since the mod's warning dialog and any Lua error show up on screen there.

## Resources

Captures are memory hungry during the tiling step. On a 16 GB host use
`--maxthreads 4`; the default (one thread per core) can get the process OOM
killed on large maps. A 20 surface, 2 snapshot timeline produced ~2.4 GB of
tiles, so give the output volume room.
