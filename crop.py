import multiprocessing as mp
import os
import time
from argparse import Namespace
from functools import partial
from pathlib import Path
from shutil import get_terminal_size as tsize

import psutil
from PIL import Image

from progress import Progress

ext = ".png"


def work(line, folder, progressQueue):
    arg = line.rstrip("\n").split(" ", 5)
    path = Path(folder, arg.pop(5))
    arg = list(map(int, arg[:4]))
    top, left, width, height = arg
    try:
        Image.open(path).convert("RGB").crop(
            (top, left, top + width, left + height)
        ).save(path)
    except IOError:
        progressQueue.put(False, True)
        return line
    except:
        progressQueue.put(False, True)
        import traceback

        traceback.print_exc()
        pass
        return False
    progressQueue.put(True, True)
    return False


def crop(outFolder, timestamp, surface, daytime, basePath=None, args: Namespace = Namespace()):

    psutil.Process(os.getpid()).nice(psutil.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 10)

    subname = Path(timestamp, surface, daytime)
    toppath = Path(
        basePath if basePath else Path(__file__, "..", "..", "..", "script-output", "FactorioMaps").resolve(),
        outFolder,
    )

    imagePath = Path(toppath, "Images")

    datapath = Path(imagePath, subname, "crop.txt")
    maxthreads = args.cropthreads if args.cropthreads else args.maxthreads

    while not datapath.exists():
        time.sleep(1)

    bar = Progress("crop")

    files = []
    with datapath.open("r", encoding="utf-8") as data:
        assert data.readline().rstrip("\n") == "v2"
        for line in data:
            files.append(line)

    pool = mp.Pool(processes=maxthreads)

    m = mp.Manager()
    progressQueue = m.Queue()
    originalSize = len(files)
    doneSize = 0

    try:
        while len(files) > 0:
            workers = pool.map_async(
                partial(work, folder=imagePath, progressQueue=progressQueue),
                files,
                128,
            )
            for _ in range(len(files)):
                if progressQueue.get(True):
                    doneSize += 1
                    bar.update(float(doneSize) / originalSize)
            workers.wait()
            files = [x for x in workers.get() if x]
            if len(files) > 0:
                time.sleep(10 if len(files) > 1000 else 1)
        bar.done()
    except KeyboardInterrupt:

        time.sleep(0.2)
        print(f"Keyboardinterrupt caught with {len(files)} files left.")
        if len(files) < 40:
            for line in files:
                print(line)

        raise
