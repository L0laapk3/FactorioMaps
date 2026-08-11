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

## Options

Everything after the image name goes straight to `auto.py`, so every flag in
the main README works unchanged. The ones that matter most here:

| flag | effect |
| --- | --- |
| `--dayonly` | skip the night pass, roughly halves the run |
| `--nightonly` | skip the day pass |
| `--all-surfaces` | every charted planet and space platform |
| `--surface NAME` | one specific surface, repeatable |
| `--hd` | 64 instead of 32 pixels per tile, much slower and much bigger |
| `--maxthreads N` | cap tiling threads, use 4 on a 16 GB host |
| `--no-tags` | leave map labels out |
| `--default-timestamp N` | which snapshot the page opens on, -1 is newest |
| `--delete` | wipe the output folder before starting |

```bash
docker compose run --rm factoriomaps --no-update --all-surfaces --dayonly mymap save1 save2
```

For compose or cron, where overriding the command is awkward, `FACTORIOMAPS_ARGS`
holds the same flags:

```yaml
environment:
  FACTORIOMAPS_ARGS: "--no-update --all-surfaces --dayonly --maxthreads 4"
command: ["mymap", "mysave"]
```

Anything on the command line is appended after those, so it wins.

Two container specific switches: `ENABLE_VNC=1` to watch a run, and
`LOG_TIMESTAMPS=0` to drop the timestamp prefix from the log.

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

## GPU vs software rendering

Measured on an Intel UHD 620 (Whiskey Lake) with 8 cores, capturing 7 surfaces
day only from the same save, two runs each, alternating:

| phase | GPU (VirtualGL) | software (llvmpipe) |
| --- | --- | --- |
| save loading | 74–76s | 91s |
| in game (load, prescan, render) | 496–508s | 667s |
| tiling after the game exits | 23s | 22s |
| **total** | **531s / 541s** | **701s / 699s** |

Software rendering costs about 30% wall clock on this hardware, so it is a
slowdown rather than a blocker. The tiling phase is identical either way, which
is the sanity check: it is pure CPU work and should not care about the renderer.
The gap widens with `--hd`, more surfaces, or a faster GPU.
