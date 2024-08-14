# Factorio Maps
![image](https://user-images.githubusercontent.com/6313423/46447780-0d723880-c784-11e8-8e6f-2b35d24f25b9.png)
This [Factorio](http://www.factorio.com/) mod turns your factory into a timeline! You can view the map locally or upload it to a web server.

Mod portal link: https://mods.factorio.com/mod/L0laapk3_FactorioMaps

# How to Install
**Note that this program now only runs on 64 bit python version 3.6 or higher.**
1. Download FactorioMaps to `%appdata%\mods\`, either from the [mod portal](https://mods.factorio.com/mod/L0laapk3_FactorioMaps) (The mod does not need to be enabled to work) and then unzipping it, or from [the github releases page](https://github.com/L0laapk3/FactorioMaps/releases).
1. Install the latest version of [**64 bit** python **3**](https://www.python.org/downloads/).
Make sure to do a select the "add python to PATH" and "install pip" options.
1. Inside the factoriomaps folder, install the required pip packages: `python -m pip install --upgrade -r requirements.txt`.

# How to Use
1. Make sure you close factorio before starting the process.
1. Navigate to the FactorioMaps folder (`%appdata%\Factorio\mods\FactorioMaps_x.x.x`). Unzip it if you haven't done that already.
1. Open a command line by typing cmd in the address bar and pressing enter. ![opening cmd](https://user-images.githubusercontent.com/6313423/46446227-6ab5bc00-c77b-11e8-982e-b040f964a778.png)
1. Run `python auto.py`. Some syntax examples:
    * `python auto.py` Generate a snapshot of the latest modified map (autosaves are excluded) and store it to a folder with the same name. If the folder already exists, the snapshot will be appended to the timeline.
    * `python auto.py savename` Generate a snapshot of *savename* and store it to folder *savename*.
    * `python auto.py outfolder savename` Generate a snapshot of *savename* and store it to folder *outfolder*.
    * `python auto.py outfolder savename1 savename2 savename3` Generate timeline snapshots of *savename1*, *savename2*, *savename3* in that order, and store it to folder *outfolder*.
    * `python auto.py outfolder savename*` Generate timeline snapshots of all savefiles that match the glob pattern `savename*` in natural order, and store it to folder *outfolder*.
    * `python auto.py --factorio=PATH` Same as `python auto.py`, but will use `factorio.exe` from *PATH* instead of attempting to find it in common locations.
    * `python auto.py --verbose` Displays factoriomaps related logs.
    * `python auto.py --verbosegame` Displays *all* game logs.
    * `python auto.py --basepath=PATH` Same as `python auto.py`, but will output to *PATH* instead of `script-output\FactorioMaps`. Not recommended to use.

1. An `index.html` will be created in `%appdata%\Factorio\script-output\FactorioMaps\mapName`. Enjoy!

# Configuration
Heres a list of flags that `auto.py` can accept:
*Options with a \* do not have an effect when appending to existing timelapses.*

| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;flag&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Description |
| --- | --- |
| `--dayonly`*\** | Do not take nighttime screenshots (For now, this setting needs to be the same across one timeline). |
| `--nightonly`*\** | Do not take daytime screenshots. |
| `--hd`*\** | Take screenshots of resolution 64 x 64 pixels per in-game tile instead of 32 x 32 to match the resolution of the newer HD textures. |
| `--no-altmode` | Hides entity info (alt mode) |
| `--no-tags` | Hides map tags |
| `--default-timestamp=-1` | Snapshot that will be loaded by the webpage by default. Negative values indicate newest snapshots, so -1 indicates the newest map while 0 indicates the oldest map. |
| `--build-range=5.2`*\** | The maximum range from buildings around which pictures are saved (in chunks, 32 by 32 in-game tiles). |
| `--connect-range=1.2`*\** | The maximum range from connection buildings (rails, electric poles) around which pictures are saved. |
| `--tag-range=5.2`*\** | The maximum range from mapview tags around which pictures are saved. |
| `--surface=nauvis` | Used to capture other surfaces. If left empty, the surface the player is standing on will be used. To capture multiple surfaces, use the argument multiple times: `--surface=nauvis --surface="Factory floor 1"`. To find out the names of surfaces, use the command `/c for _,s in pairs(game.surfaces) do game.print(s.name) end`. |
| `--factorio=PATH` | Use `factorio.exe` from *PATH* instead of attempting to find it in common locations. |
| `--modpath=PATH` | Use *PATH* as the mod folder. |
| `--basepath=RELPATH` | Output to `script-output\RELPATH` instead of `script-output\FactorioMaps`. (Factorio cannot output outside of `script-output`) |
| `--date=dd/mm/yy` | Date attached to the snapshot, default is today. |
| `--steam` | Only use factorio binary from steam. |
| `--standalone` | Only use standalone factorio binary. |
| `--verbose` | Displays factoriomaps script logs. |
| `--verbosegame` | Displays *all* game logs. |
| `--no-update` | Skips the update check. |
| `--maxthreads=N` | Sets the number of threads used for all steps. By default this is equal to the amount of logical processor cores available. |
| `--cropthreads=N` | Sets the number of threads used for the crop step. |
| `--refthreads=N` | Sets the number of threads used for the crossreferencing step. |
| `--zoomthreads=N` | Sets the number of threads used for the zoom step. |
| `--screenshotthreads=N` | Set the number of screenshotting threads factorio uses. |
| `--delete` | Deletes the output folder specified before running the script. |
| `--dry` | Skips starting factorio, making screenshots and doing the main steps, only execute setting up and finishing of script. |
| `--force-lib-update` | Forces an update of the web dependencies. |
| `--temp-dir` | Use a custom temporary directory. |

Image quality settings can be changed in the top of `zoom.py`.

# Result folder estimates
You can expect the resulting folders to take up approx. (very rough estimate) 15 times the savefile size per timestamp per daytime for day images and 10 times for night images. The intermediate total disk usage will be much higher, 10 times the final result or more. If this is a problem for you, go put a +1 on [#46](https://github.com/L0laapk3/FactorioMaps/issues/46).
Of course the processing time depends very heavely on your system specs, but a rough estimate is an hour per timestamp per daytime per 50 MB of savefile.

# Hosting this on a server
If you wish to host your map for other people to a server, you need to take into account the following considerations: (You can change these once in `index.html.template` and they will be used for all future snapshots.)
1. Of the files that this program generates, the files required to be hosted are:
    * `index.html`
    * `index.css`
    * `index.js`
    * `mapInfo.js`
    * All __images__ in `Images\`.
    * All files in `lib\`.
    All other files, including txt and other non-image files in `Images\`, are not used by the client. Some of them are temporary files, some of them are used as savestate to create additional snapshots on the timeline.

# Known mods that make use of the API to improve compability
    * Factorissimo ⩾2.3.5: Able to render the inside of factory buildings recursively.
    * Your mod? If you want to have a chat, you can always find me on discord: L0laapk3#2010

# Known limitations
* If you only have the steam version of factorio, steam will ask you to confirm the arguments everytime the script tries to start up. The popup window will sometimes not focus properly. Please press alt tab a couple of times until it shows up. The only way to get around this is to install the standalone version of factorio.
* If the program crashes while making a snapshot, it is very likely to leave timelines behind in a 'bricked' state and will probably mess up future snapshots. The easiest way is to simply start over and regenerate all the snapshots from old savefiles. If thats not a possibility, feel free to contact me on discord (L0laapk3#2010) or create an Issue, I'll do my best to help you out.
* Running this on headless servers is not possible due to factorio limitations.
* Not all factorio rich text is supported [#93](https://github.com/L0laapk3/FactorioMaps/issues/93).

# Issues
If you have problems or questions setting things up, feel free to reach out to me on discord at L0laapk3#2010.
If you believe you have found a bug, inconsistency, something unclear or anything else, please try generating a map to a new empty output folder (If you need help recovering bricked timelapses, please reach out to me). If the problem persists, please submit an issue to the [Issue tracker](https://github.com/L0laapk3/FactorioMaps/issues).
