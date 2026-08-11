import json
import math
import multiprocessing as mp
from argparse import Namespace
import os
from pathlib import Path
from shutil import get_terminal_size as tsize
from sys import platform as _platform

import numpy
import psutil
from PIL import Image
from turbojpeg import TurboJPEG

from progress import Progress

maxQuality = False  		# Set this to true if you want to compress/postprocess the images yourself later
useBetterEncoder = True 	# Slower encoder that generates smaller images.

quality = 80

EXT = ".png"
OUTEXT = ".jpg"     		# format='JPEG' is hardcoded in places, meed to modify those, too. Most parameters are not supported outside jpeg.
THUMBNAILEXT = ".png"

BACKGROUNDCOLOR = (27, 45, 51)
THUMBNAILSCALE = 2

MINRENDERBOXSIZE = 8


def printErase(arg):
    try:
        tsiz = tsize()[0]
        print("\r{}{}\n".format(arg, " " * (tsiz*math.ceil(len(arg)/tsiz)-len(arg) - 1)), end="", flush=True)
    except:
        #raise
        pass


# the bundled libraries are 64 bit x86, fall back to a system libturbojpeg elsewhere
# (macOS, and linux on anything that is not x86-64).
def loadTurboJpeg():
    def bundled(name):
        path = Path(__file__, "..", "mozjpeg", name).resolve()
        return path.as_posix() if path.is_file() else None

    if os.name == "nt":
        candidates = [bundled("turbojpeg.dll")]
    elif _platform == "darwin":
        candidates = [
            "/opt/homebrew/opt/jpeg-turbo/lib/libturbojpeg.dylib",
            "/usr/local/opt/jpeg-turbo/lib/libturbojpeg.dylib",
        ]
    else:
        candidates = [
            bundled("libturbojpeg.so"),
            "/usr/lib/x86_64-linux-gnu/libturbojpeg.so.0",
            "/usr/lib/aarch64-linux-gnu/libturbojpeg.so.0",
            "/usr/lib64/libturbojpeg.so.0",
        ]
    candidates.append(None)  # None = let PyTurboJPEG search the default locations

    for libPath in candidates:
        if libPath is None or Path(libPath).is_file() or not Path(libPath).parent.exists():
            try:
                return TurboJPEG(libPath)
            except (OSError, RuntimeError):
                continue
    hint = "brew install jpeg-turbo" if _platform == "darwin" else "install the libturbojpeg package"
    raise RuntimeError(f"libturbojpeg could not be loaded. Try: {hint}")

jpeg = loadTurboJpeg()


def saveCompress(img, path: Path):
    if maxQuality:  # do not waste any time compressing the image
        return img.save(path, subsampling=0, quality=100)

    outFile = path.open("wb")
    outFile.write(jpeg.encode(numpy.array(img)[:, :, ::-1].copy()))
    outFile.close()


def simpleZoom(workQueue):
    for (folder, start, stop, filename) in workQueue:
        path = Path(folder, str(start), filename)
        img = Image.open(path.with_suffix(EXT), mode="r").convert("RGB")
        if OUTEXT != EXT:
            saveCompress(img, path.with_suffix(OUTEXT))
            path.with_suffix(EXT).unlink()

        for z in range(start - 1, stop - 1, -1):
            if img.size[0] >= MINRENDERBOXSIZE * 2 and img.size[1] >= MINRENDERBOXSIZE * 2:
                img = img.resize((img.size[0] // 2, img.size[1] // 2), Image.Resampling.LANCZOS)
            zFolder = Path(folder, str(z))
            if not zFolder.exists():
                zFolder.mkdir(parents=True)
            saveCompress(img, Path(zFolder, filename).with_suffix(OUTEXT))


def zoomRenderboxes(daytimeSurfaces, toppath, timestamp, subpath, args):
    with Path(toppath, "mapInfo.json").open("r+", encoding="utf-8") as mapInfoFile:
        mapInfo = json.load(mapInfoFile)

        outFile = Path(toppath, "mapInfo.out.json")
        if outFile.exists():
            with outFile.open("r", encoding="utf-8") as mapInfoOutFile:
                outInfo = json.load(mapInfoOutFile)
        else:
            outInfo = {"maps": {}}

        mapLayer = None
        mapIndex = None

        for i, m in enumerate(mapInfo["maps"]):
            if m["path"] == timestamp:
                mapLayer = m
                mapIndex = str(i)

        if not mapLayer or not mapIndex:
            raise Exception("mapLayer or mapIndex missing")

        if mapIndex not in outInfo["maps"]:
            outInfo["maps"][mapIndex] = {"surfaces": {}}

        zoomWork = set()
        for daytime, activeSurfaces in daytimeSurfaces.items():
            surfaceZoomLevels = {}
            for surfaceName in activeSurfaces:
                surfaceZoomLevels[surfaceName] = (
                    mapLayer["surfaces"][surfaceName]["zoom"]["max"]
                    - mapLayer["surfaces"][surfaceName]["zoom"]["min"]
                )

            for surfaceName, surface in mapLayer["surfaces"].items():
                if "links" in surface:

                    if surfaceName not in outInfo["maps"][mapIndex]["surfaces"]:
                        outInfo["maps"][mapIndex]["surfaces"][surfaceName] = {}
                    if "links" not in outInfo["maps"][mapIndex]["surfaces"][surfaceName]:
                        outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"] = []

                    for linkIndex, link in enumerate(surface["links"]):
                        if link["type"] == "link_renderbox_area" and "zoom" in link:
                            totalZoomLevelsRequired = 0
                            for zoomSurface, zoomLevel in link["maxZoomFromSurfaces"].items():
                                if zoomSurface in surfaceZoomLevels:
                                    totalZoomLevelsRequired = max(
                                        totalZoomLevelsRequired,
                                        zoomLevel + surfaceZoomLevels[zoomSurface],
                                    )

                            if not outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex]:
                                outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex] = {}
                            if "zoom" not in outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex]:
                                outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex]["zoom"] = {}

                            link["zoom"]["min"] = link["zoom"]["max"] - totalZoomLevelsRequired
                            outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex]["zoom"]["min"] = link["zoom"]["min"]

                            # an assumption is made that the total zoom levels required doesnt change between snapshots.
                            if (link if "path" in link else outInfo["maps"][mapIndex]["surfaces"][surfaceName]["links"][linkIndex])["path"] == timestamp:
                                zoomWork.add(
                                    (
                                        Path(
                                            subpath,
                                            mapLayer["path"],
                                            link["toSurface"],
                                            daytime if link["daynight"] else "day",
                                            "renderboxes",
                                        ).resolve(),
                                        link["zoom"]["max"],
                                        link["zoom"]["min"],
                                        link["filename"],
                                    )
                                )

        with outFile.open("w", encoding="utf-8") as mapInfoOutFile:
            json.dump(outInfo, mapInfoOutFile)
            mapInfoOutFile.truncate()

    maxthreads = args.zoomthreads if args.zoomthreads else args.maxthreads
    processes = []
    zoomWork = list(zoomWork)
    for i in range(0, min(maxthreads, len(zoomWork))):
        p = mp.Process(target=simpleZoom, args=(zoomWork[i::maxthreads],))
        p.start()
        processes.append(p)
    for p in processes:
        p.join()


def work(basepath, pathList, surfaceName, daytime, size, start, stop, last, chunk, keepLast=False):
    chunksize = 2 ** (start - stop)
    if start > stop:
        for k in range(start, stop, -1):
            x = chunksize * chunk[0]
            y = chunksize * chunk[1]
            for j in range(y, y + chunksize, 2):
                for i in range(x, x + chunksize, 2):

                    coords = [(0, 0), (1, 0), (0, 1), (1, 1)]
                    paths = [
                        Path(
                            basepath,
                            pathList[0],
                            surfaceName,
                            daytime,
                            str(k),
                            str(i + coord[0]),
                            str(j + coord[1]),
                        ).with_suffix(EXT)
                        for coord in coords
                    ]

                    if any(path.exists() for path in paths):

                        if not Path(basepath, pathList[0], surfaceName, daytime, str(k - 1), str(i // 2)).exists():
                            try:
                                Path(basepath, pathList[0], surfaceName, daytime, str(k - 1), str(i // 2)).mkdir(parents=True)
                            except OSError:
                                pass

                        isOriginal = []
                        for m in range(len(coords)):
                            isOriginal.append(paths[m].is_file())
                            if not isOriginal[m]:
                                for n in range(1, len(pathList)):
                                    paths[m] = Path(basepath, pathList[n], surfaceName, daytime, str(k), str(i + coords[m][0]), str(j + coords[m][1])).with_suffix(OUTEXT)
                                    if paths[m].is_file():
                                        break

                        result = Image.new("RGB", (size, size), BACKGROUNDCOLOR)

                        images = []
                        for m in range(len(coords)):
                            if paths[m].is_file():
                                img = Image.open(paths[m], mode="r").convert("RGB")
                                result.paste(
                                    box=(
                                        coords[m][0] * size // 2,
                                        coords[m][1] * size // 2,
                                    ),
                                    im=img.resize(
                                        (size // 2, size // 2), Image.Resampling.LANCZOS
                                    ),
                                )

                                if isOriginal[m]:
                                    images.append((img, paths[m]))

                        if k == last + 1:
                            saveCompress(result, Path(basepath, pathList[0], surfaceName, daytime, str(k - 1), str(i // 2), str(j // 2)).with_suffix(OUTEXT))
                        if OUTEXT != EXT and (k != last + 1 or keepLast):
                            result.save(Path(basepath, pathList[0], surfaceName, daytime, str(k - 1), str(i // 2), str(j // 2), ).with_suffix(EXT))

                        if OUTEXT != EXT:
                            for img, path in images:
                                saveCompress(img, path.with_suffix(OUTEXT))
                                path.unlink()

            chunksize = chunksize // 2
    elif stop == last:
        path = Path(basepath, pathList[0], surfaceName, daytime, str(start), str(chunk[0]), str(chunk[1]))
        img = Image.open(path.with_suffix(EXT), mode="r").convert("RGB")
        saveCompress(img, path.with_suffix(OUTEXT))
        path.with_suffix(EXT).unlink()


def thread(basepath, pathList, surfaceName, daytime, size, start, stop, last, allChunks, counter, resultQueue, keepLast=False):
    #print(start, stop, chunks)
    while True:
        with counter.get_lock():
            i = counter.value - 1
            if i < 0:
                return
            counter.value = i
        chunk = allChunks[i]
        work(basepath, pathList, surfaceName, daytime, size, start, stop, last, chunk, keepLast)
        resultQueue.put(True)




def zoom(
    outFolder: Path,
    timestamp: str = None,
    surfaceReference: str = None,
    daytimeReference: str = None,
    basepath: Path = None,
    needsThumbnail: bool = True,
    args: Namespace = Namespace(),
):

    psutil.Process(os.getpid()).nice(psutil.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 10)

    workFolder = basepath if basepath else Path(__file__, "..", "..", "..", "script-output", "FactorioMaps").resolve()

    topPath = Path(workFolder, outFolder)
    dataPath = Path(topPath, "mapInfo.json")
    imagePath = Path(topPath, "Images")
    maxthreads = args.zoomthreads if args.zoomthreads else args.maxthreads

    with dataPath.open("r", encoding="utf-8") as f:
        data = json.load(f)
    for mapIndex, map in enumerate(data["maps"]):
        if timestamp is None or map["path"] == timestamp:
            for surfaceName, surface in map["surfaces"].items():
                if surfaceReference is None or surfaceName == surfaceReference:
                    maxzoom = surface["zoom"]["max"]
                    minzoom = surface["zoom"]["min"]

                    daytimes = []
                    if "day" in surface:
                        daytimes.append("day")
                    if "night" in surface:
                        daytimes.append("night")
                    for daytime in daytimes:
                        if daytimeReference is None or daytime == daytimeReference:
                            if not Path(topPath, "Images", str(map["path"]), surfaceName, daytime, str(maxzoom - 1)).is_dir():

                                bar = Progress("zoom")

                                generateThumbnail = (
                                    needsThumbnail
                                    and mapIndex == len(data["maps"]) - 1
                                    and surfaceName
                                    == (
                                        "nauvis"
                                        if "nauvis" in map["surfaces"]
                                        else sorted(map["surfaces"].keys())[0]
                                    )
                                    and daytime == daytimes[0]
                                )

                                allBigChunks = {}
                                minX = float("inf")
                                maxX = float("-inf")
                                minY = float("inf")
                                maxY = float("-inf")
                                imageSize: int = None
                                for xStr in Path(imagePath, str(map["path"]), surfaceName, daytime, str(maxzoom)).iterdir():
                                    x = int(xStr.name)
                                    minX = min(minX, x)
                                    maxX = max(maxX, x)
                                    for yStr in Path(imagePath, str(map["path"]), surfaceName, daytime, str(maxzoom), xStr).iterdir():
                                        if imageSize is None:
                                            imageSize = Image.open(Path(imagePath, str(map["path"]), surfaceName, daytime, str(maxzoom), xStr, yStr), mode="r").size[0]
                                        y = int(yStr.stem)
                                        minY = min(minY, y)
                                        maxY = max(maxY, y)
                                        allBigChunks[
                                            (
                                                x >> maxzoom-minzoom,
                                                y >> maxzoom-minzoom,
                                            )
                                        ] = True

                                if len(allBigChunks) <= 0:
                                    continue

                                pathList = []
                                for otherMapIndex in range(mapIndex, -1, -1):
                                    pathList.append(str(data["maps"][otherMapIndex]["path"]))

                                threadsplit = 0
                                while 4**threadsplit * len(allBigChunks) < maxthreads:
                                    threadsplit = threadsplit + 1
                                threadsplit = min(max(maxzoom - minzoom - 3, 0), threadsplit + 3)
                                allChunks = []
                                for pos in list(allBigChunks):
                                    for i in range(2**threadsplit):
                                        for j in range(2**threadsplit):
                                            allChunks.append(
                                                (
                                                    pos[0] * (2**threadsplit) + i,
                                                    pos[1] * (2**threadsplit) + j,
                                                )
                                            )

                                threads = min(len(allChunks), maxthreads)
                                processes = []
                                originalSize = len(allChunks)

                                # print(("%s %s %s %s" % (pathList[0], str(surfaceName), daytime, pathList)))
                                # print(("%s-%s (total: %s):" % (start, stop + threadsplit, len(allChunks))))
                                counter = mp.Value("i", originalSize)
                                resultQueue = mp.Queue()
                                for _ in range(0, threads):
                                    p = mp.Process(
                                        target=thread,
                                        args=(
                                            imagePath,
                                            pathList,
                                            surfaceName,
                                            daytime,
                                            imageSize,
                                            maxzoom,
                                            minzoom + threadsplit,
                                            minzoom,
                                            allChunks,
                                            counter,
                                            resultQueue,
                                            generateThumbnail,
                                        ),
                                    )
                                    p.start()
                                    processes.append(p)

                                doneSize = 0
                                for _ in range(originalSize):
                                    resultQueue.get(True)
                                    doneSize += 1
                                    bar.update(float(doneSize) / originalSize * 0.98)

                                for p in processes:
                                    p.join()

                                if threadsplit > 0:
                                    # print(("finishing up: %s-%s (total: %s)" % (stop + threadsplit, stop, len(allBigChunks))))
                                    processes = []
                                    i = len(allBigChunks) - 1
                                    for chunk in list(allBigChunks):
                                        p = mp.Process(
                                            target=work,
                                            args=(
                                                imagePath,
                                                pathList,
                                                surfaceName,
                                                daytime,
                                                imageSize,
                                                minzoom + threadsplit,
                                                minzoom,
                                                minzoom,
                                                chunk,
                                                generateThumbnail,
                                            ),
                                        )
                                        i = i - 1
                                        p.start()
                                        processes.append(p)
                                    for p in processes:
                                        p.join()

                                if generateThumbnail:
                                    printErase("generating thumbnail")
                                    minzoompath = Path(
                                        imagePath,
                                        str(map["path"]),
                                        surfaceName,
                                        daytime,
                                        str(minzoom),
                                    )

                                    if imageSize is None:
                                        raise Exception("Missing imageSize for thumbnail generation")

                                    thumbnail = Image.new(
                                        "RGB",
                                        (
                                            (maxX - minX + 1) * imageSize >> maxzoom-minzoom,
                                            (maxY - minY + 1) * imageSize >> maxzoom-minzoom,
                                        ),
                                        BACKGROUNDCOLOR,
                                    )
                                    bigMinX = minX >> maxzoom-minzoom
                                    bigMinY = minY >> maxzoom-minzoom
                                    xOffset = ((bigMinX * imageSize << maxzoom-minzoom) - minX * imageSize) >> maxzoom-minzoom
                                    yOffset = ((bigMinY * imageSize << maxzoom-minzoom) - minY * imageSize) >> maxzoom-minzoom
                                    for chunk in list(allBigChunks):
                                        path = Path(minzoompath, str(chunk[0]), str(chunk[1])).with_suffix(EXT)
                                        thumbnail.paste(
                                            box=(
                                                xOffset + (chunk[0] - bigMinX) * imageSize,
                                                yOffset + (chunk[1] - bigMinY) * imageSize,
                                            ),
                                            im=Image.open(path, mode="r")
                                            .convert("RGB")
                                            .resize((imageSize, imageSize), Image.Resampling.LANCZOS),
                                        )

                                        if OUTEXT != EXT:
                                            path.unlink()

                                    thumbnail.save(Path(imagePath, "thumbnail" + THUMBNAILEXT))

                                bar.done()
