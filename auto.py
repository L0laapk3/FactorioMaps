
import sys

if sys.maxsize <= 2**32 or sys.hexversion < 0x3060000:
	raise Exception("64 bit Python 3.6 or higher is required for this script.")

import os
import traceback
import pkg_resources
from pkg_resources import DistributionNotFound, VersionConflict
from pathlib import Path

try:
	with Path(__file__, "..", "requirements.txt").resolve().open("r", encoding="utf-8") as f:
		pkg_resources.require(f.read().splitlines())
except (DistributionNotFound, VersionConflict) as ex:
	traceback.print_exc()
	print("\nDependencies not met. Run `pip install -r requirements.txt` to install missing dependencies.")
	sys.exit(1)

import glob
import argparse
import configparser
import datetime
import json
import errno
import math
import multiprocessing as mp
import random
import re
import string
import signal
import subprocess
import tempfile
from tempfile import TemporaryDirectory
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from argparse import Namespace
from shutil import copy, copytree
from shutil import get_terminal_size as tsize
from shutil import rmtree
from socket import timeout
from subprocess import call
from zipfile import ZipFile

import psutil
from PIL import Image, ImageChops

from crop import crop
from ref import ref
from updateLib import update as updateLib
from zoom import zoom, zoomRenderboxes

userFolder = Path(__file__, "..", "..", "..").resolve()

def naturalSort(l):
	convert = lambda text: int(text) if text.isdigit() else text.lower()
	alphanum_key = lambda key: [ convert(c) for c in re.split('(\d+)', key) ]
	return sorted(l, key = alphanum_key)

def printErase(arg):
	try:
		tsiz = tsize()[0]
		print("\r{}{}\n".format(arg, " " * (tsiz*math.ceil(len(arg)/tsiz)-len(arg) - 1)), end="", flush=True)
	except:
		#raise
		pass


def startGameAndReadGameLogs(results, condition, exeWithArgs, isSteam, tmpDir, pidBlacklist, rawTags, args):

	pipeOut, pipeIn = os.pipe()
	p = subprocess.Popen(exeWithArgs, stdout=pipeIn)

	printingStackTraceback = False
	# TODO: keep printing multiline stuff until new print detected
	prevPrinted = False
	def handleGameLine(line, isFirst):
		if isFirst and not re.match(r'^ *\d+\.\d{3} \d{4}-\d\d-\d\d \d\d:\d\d:\d\d; Factorio (\d+\.\d+\.\d+) \(build (\d+), [^)]+\)$', line):
			suggestion = "maybe your version is outdated or too new?"
			if line.endswith('Error Util.cpp:83: weakly_canonical: Incorrect function.'):
				suggestion = "maybe your temp directory is on a ramdisk?"
			raise RuntimeError(f"Unrecognised output from factorio ({suggestion})\n\nOutput from factorio:\n{line}")

		nonlocal prevPrinted
		line = line.rstrip('\n')
		if re.match(r'^\ *\d+(?:\.\d+)? *[^\n]*$', line) is None:
			if prevPrinted:
				printErase(line)
			return

		prevPrinted = False

		m = re.match(r'^\ *\d+(?:\.\d+)? *Script *@__L0laapk3_FactorioMaps__\/data-final-fixes\.lua:\d+: FactorioMaps_Output_RawTagPaths:([^:]+):(.*)$', line, re.IGNORECASE)
		if m is not None:
			rawTags[m.group(1)] = m.group(2)
			if rawTags["__used"]:
				raise Exception("Tags added after they were used.")
		else:
			if printingStackTraceback or line == "stack traceback:":
				printErase("[GAME] %s" % line)
				prevPrinted = True
				return True
			m = re.match(r'^\ *\d+(?:\.\d+)? *Script *@__L0laapk3_FactorioMaps__\/(.*?)(?:(\[info\]) ?(.*))?$', line, re.IGNORECASE)
			if m is not None and m.group(2) is not None:
				printErase(m.group(3))
				prevPrinted = True
			elif m is not None and args.verbose:
				printErase(m.group(1))
				prevPrinted = True
			elif line.lower() in ("error", "warn", "exception", "fail", "invalid") or (args.verbosegame and len(line) > 0):
				printErase("[GAME] %s" % line)
				prevPrinted = True
		return False


	with os.fdopen(pipeOut, 'r') as pipef:

		if isSteam:
			printErase("using steam launch hack.")

			attrs = ('pid', 'name', 'create_time')

			# on some devices, the previous check wasn't enough apparently, so explicitely wait until the log file is created.
			while not os.path.exists(os.path.join(tmpDir, "factorio-current.log")):
				time.sleep(0.4)

			oldest = None
			pid = None
			while pid is None:
				for proc in psutil.process_iter(attrs=attrs):
					pinfo = proc.as_dict(attrs=attrs)
					if pinfo["name"] == "factorio.exe" and pinfo["pid"] not in pidBlacklist and (pid is None or pinfo["create_time"] < oldest):
						oldest = pinfo["create_time"]
						pid = pinfo["pid"]
				if pid is None:
					time.sleep(1)
			# print(f"PID: {pid}")
		else:
			pid = p.pid

		results.extend((isSteam, pid))
		with condition:
			condition.notify()

		psutil.Process(pid).nice(psutil.BELOW_NORMAL_PRIORITY_CLASS if os.name == 'nt' else 10)

		isFirstLine = True
		if isSteam:
			pipef.close()
			with Path(tmpDir, "factorio-current.log").open("r", encoding="utf-8") as f:
				while psutil.pid_exists(pid):
					where = f.tell()
					line = f.readline()
					if not line:
						time.sleep(0.4)
						f.seek(where)
					else:
						printingStackTraceback = handleGameLine(line, isFirstLine)
						isFirstLine = False

		else:
			while True:
				line = pipef.readline().rstrip("\n")
				printingStackTraceback = handleGameLine(line, isFirstLine)
				isFirstLine = False


def checkUpdate(reverseUpdateTest:bool = False):
	try:
		print("checking for updates")
		latestUpdates = json.loads(urllib.request.urlopen('https://cdn.jsdelivr.net/gh/L0laapk3/FactorioMaps@latest/updates.json', timeout=30).read())
		with Path(__file__, "..", "updates.json").resolve().open("r", encoding="utf-8") as f:
			currentUpdates = json.load(f)
		if reverseUpdateTest:
			latestUpdates, currentUpdates = currentUpdates, latestUpdates

		updates = []
		majorUpdate = False
		currentVersion = (0, 0, 0)
		for verStr, changes in currentUpdates.items():
			ver = tuple(map(int, verStr.split(".")))
			if currentVersion[0] < ver[0] or (currentVersion[0] == ver[0] and currentVersion[1] < ver[1]):
				currentVersion = ver
		for verStr, changes in latestUpdates.items():
			if verStr not in currentUpdates:
				ver = tuple(map(int, verStr.split(".")))
				updates.append((verStr, changes))
		updates.sort(key = lambda u: u[0])
		if len(updates) > 0:

			padding = max(map(lambda u: len(u[0]), updates))
			changelogLines = []
			for update in updates:
				if isinstance(update[1], str):
					updateText = update[1]
				else:
					updateText = str(("\r\n      " + " "*padding).join(update[1]))
				if updateText[0] == "!":
					majorUpdate = True
					updateText = updateText[1:]
				changelogLines.append("    %s: %s" % (update[0].rjust(padding), updateText))
			print("")
			print("")
			print("================================================================================")
			print("")
			print(("  An " + ("important" if majorUpdate else "incremental") + " update has been found!"))
			print("")
			print("  Here's what changed:")
			for line in changelogLines:
				print(line)
			print("")
			print("")
			print("  Download: https://git.io/factoriomaps")
			if majorUpdate:
				print("")
				print("  You can dismiss this by using --no-update (not recommended)")
			print("")
			print("================================================================================")
			print("")
			print("")
		if majorUpdate or reverseUpdateTest:
			exit(1)

	except (urllib.error.URLError, timeout) as e:
		print("Failed to check for updates. %s: %s" % (type(e).__name__, e))


def linkDir(src: Path, dest:Path):
	if os.name == 'nt':
		subprocess.check_call(("MKLINK", "/J", src.resolve(), dest.resolve()), stdout=subprocess.DEVNULL, shell=True)
	else:
		os.symlink(dest.resolve(), src.resolve())


def linkCustomModFolder(modpath: Path):
	print(f"Verifying mod version in custom mod folder ({modpath})")
	modPattern = re.compile(r'^L0laapk3_FactorioMaps_', flags=re.IGNORECASE)
	for entry in [entry for entry in modpath.iterdir() if modPattern.match(entry.name)]:
		print("Found other factoriomaps mod in custom mod folder, deleting.")
		path = Path(modpath, entry)
		if path.is_file() or path.is_symlink():
			path.unlink()
		elif path.is_dir():
			rmtree(path)
		else:
			raise Exception(f"Unable to remove {path} unknown type")

	linkDir(Path(modpath, Path('.').resolve().name), Path("."))


def changeModlist(modpath: Path,newState: bool):
	print(f"{'Enabling' if newState else 'Disabling'} FactorioMaps mod")
	done = False
	modlistPath = Path(modpath, "mod-list.json")
	with modlistPath.open("r", encoding="utf-8") as f:
		modlist = json.load(f)
	for mod in modlist["mods"]:
		if mod["name"] == "L0laapk3_FactorioMaps":
			mod["enabled"] = newState
			done = True
			break
	if not done:
		modlist["mods"].append({"name": "L0laapk3_FactorioMaps", "enabled": newState})
	with modlistPath.open("w", encoding="utf-8") as f:
		json.dump(modlist, f, indent=2)


def buildAutorun(args: Namespace, workFolder: Path, outFolder: Path, isFirstSnapshot: bool, daytime: str):
	printErase("Building autorun.lua")
	mapInfoPath = Path(workFolder, "mapInfo.json")
	if mapInfoPath.is_file():
		with mapInfoPath.open("r", encoding='utf-8') as f:
			mapInfoLua = re.sub(r'"([^"]+)" *:', lambda m: '["'+m.group(1)+'"] = ', f.read().replace("[", "{").replace("]", "}"))
			# TODO: Update for new argument parsing
#			if isFirstSnapshot:
#				f.seek(0)
#				mapInfo = json.load(f)
#				if "options" in mapInfo:
#					for kwarg in changedKwargs:
#						if kwarg in ("hd", "dayonly", "nightonly", "build-range", "connect-range", "tag-range"):
#							printErase("Warning: flag '" + kwarg + "' is overriden by previous setting found in existing timeline.")
	else:
		mapInfoLua = "{}"

	isFirstSnapshot = False

	chunkCachePath = Path(workFolder, "chunkCache.json")
	if chunkCachePath.is_file():
		with chunkCachePath.open("r", encoding="utf-8") as f:
			chunkCache = re.sub(r'"([^"]+)" *:', lambda m: '["'+m.group(1)+'"] = ', f.read().replace("[", "{").replace("]", "}"))
	else:
		chunkCache = "{}"

	def lowerBool(value: bool):
		return str(value).lower()

	with Path(__file__, "..", "autorun.lua").resolve().open("w", encoding="utf-8") as f:
		surfaceString = '{"' + '", "'.join(args.surface) + '"}' if args.surface else "nil"
		autorunString = \
			f'''fm.autorun = {{
			HD = {lowerBool(args.hd)},
			daytime = "{daytime}",
			alt_mode = {lowerBool(args.altmode)},
			tags = {lowerBool(args.tags)},
			around_tag_range = {args.tag_range},
			around_build_range = {args.build_range},
			around_connect_range = {args.connect_range},
			connect_types = {{"lamp", "electric-pole", "radar", "straight-rail", "curved-rail", "rail-signal", "rail-chain-signal", "locomotive", "cargo-wagon", "fluid-wagon", "car"}},
			date = "{datetime.datetime.strptime(args.date, "%d/%m/%y").strftime("%d/%m/%y")}",
			surfaces = {surfaceString},
			name = "{str(outFolder) + "/"}",
			mapInfo = {mapInfoLua.encode("utf-8").decode("unicode-escape")},
			chunkCache = {chunkCache}
			}}'''
		f.write(autorunString)
		if args.verbose:
			printErase(autorunString)


def buildConfig(args: Namespace, tmpDir, basepath):
	printErase("Building config.ini")
	if args.verbose > 2:
		print(f"Using temporary directory '{tmpDir}'")
	configPath = Path(tmpDir, "config","config.ini")
	configPath.parent.mkdir(parents=True)

	config = configparser.ConfigParser()
	config.read(Path(args.config_path, "config.ini"))

	if "interface" not in config:
		config["interface"] = {}
	config["interface"]["show-tips-and-tricks"] = "false"

	if "path" not in config:
		config["path"] = {}
	config["path"]["write-data"] = tmpDir

	config["path"]["script-output"] = str(basepath)

	if "graphics" not in config:
		config["graphics"] = {}
	config["graphics"]["screenshots-threads-count"] = str(args.screenshotthreads if args.screenshotthreads else args.maxthreads)
	config["graphics"]["max-threads"] = config["graphics"]["screenshots-threads-count"]

	with configPath.open("w+", encoding="utf-8") as configFile:
		configFile.writelines(("; version=3\n", ))
		config.write(configFile, space_around_delimiters=False)

	copy(Path(userFolder, 'player-data.json'), tmpDir)

	return configPath


def auto(*args):

	lock = threading.Lock()
	def kill(pid):
		with lock:
			try:
				print("killing factorio")
				p = psutil.Process(pid)
				# psutils terminate() and is_running() check creation time
				# as well as PID, so this works correctly even if the pid
				# we pass is already dead and its PID has been reused by
				# an unrelated process.
				p.terminate()
				if p.is_running():
					p.wait()
				print("killed factorio")
			except psutil.NoSuchProcess:
				print("factorio is already dead, continuing")

	parser = argparse.ArgumentParser(description="FactorioMaps")
	daytime = parser.add_mutually_exclusive_group()
	daytime.add_argument("--dayonly", dest="night", action="store_false", help="Only take daytime screenshots.")
	daytime.add_argument("--nightonly", dest="day", action="store_false", help="Only take nighttime screenshots.")
	parser.add_argument("--hd", action="store_true", help="Take screenshots of resolution 64 x 64 pixels per in-game tile.")
	parser.add_argument("--no-altmode", dest="altmode", action="store_false", help="Hides entity info (alt mode).")
	parser.add_argument("--no-tags", dest="tags", action="store_false", help="Hides map tags")
	parser.add_argument("--default-timestamp", type=int, default=None, dest="default_timestamp", help="Snapshot that will be loaded by the webpage by default. Negative values indicate newest snapshots, so -1 indicates the newest map while 0 indicates the oldest map.")
	parser.add_argument("--build-range", type=float, default=5.2, help="The maximum range from buildings around which pictures are saved (in chunks, 32 by 32 in-game tiles).")
	parser.add_argument("--connect-range", type=float, default=1.2, help="The maximum range from connection buildings (rails, electric poles) around which pictures are saved.")
	parser.add_argument("--tag-range", type=float, default=5.2, help="The maximum range from mapview tags around which pictures are saved.")
	parser.add_argument("--surface", action="append", default=[], help="Used to capture other surfaces. If left empty, the surface the player is standing on will be used. To capture multiple surfaces, use the argument multiple times: --surface nauvis --surface 'Factory floor 1'")
	parser.add_argument("--factorio", type=lambda p: Path(p).resolve(), help="Use factorio.exe from PATH instead of attempting to find it in common locations.")
	parser.add_argument("--output-path", dest="basepath", type=lambda p: Path(p).resolve(), default=Path(userFolder, "script-output", "FactorioMaps"), help="path to the output folder (default is '..\\..\\script-output\\FactorioMaps')")
	parser.add_argument("--mod-path", "--modpath", type=lambda p: Path(p).resolve(), default=Path(userFolder, 'mods'), help="Use PATH as the mod folder. (default is '..\\..\\mods')")
	parser.add_argument("--config-path", type=lambda p: Path(p).resolve(), default=Path(userFolder, 'config'), help="Use PATH as the mod folder. (default is '..\\..\\config')")
	parser.add_argument("--date", default=datetime.date.today().strftime("%d/%m/%y"), help="Date attached to the snapshot, default is today. [dd/mm/yy]")
	parser.add_argument("--steam", default=0, action="store_true", help="Only use factorio binary from steam")
	parser.add_argument("--standalone", default=0, action="store_true", help="Only use standalone factorio binary")
	parser.add_argument('--verbose', '-v', action='count', default=0, help="Displays factoriomaps script logs.")
	parser.add_argument('--verbosegame', action='count', default=0, help="Displays all game logs.")
	parser.add_argument("--no-update", "--noupdate", dest="update", action="store_false", help="Skips the update check.")
	parser.add_argument("--reverseupdatetest", action="store_true", help=argparse.SUPPRESS)
	parser.add_argument("--maxthreads", type=int, default=mp.cpu_count(), help="Sets the number of threads used for all steps. By default this is equal to the amount of logical processor cores available.")
	parser.add_argument("--cropthreads", type=int, default=None, help="Sets the number of threads used for the crop step.")
	parser.add_argument("--refthreads", type=int, default=None, help="Sets the number of threads used for the crossreferencing step.")
	parser.add_argument("--zoomthreads", type=int, default=None, help="Sets the number of threads used for the zoom step.")
	parser.add_argument("--screenshotthreads", type=int, default=None, help="Set the number of screenshotting threads factorio uses.")
	parser.add_argument("--delete", action="store_true", help="Deletes the output folder specified before running the script.")
	parser.add_argument("--dry", action="store_true", help="Skips starting factorio, making screenshots and doing the main steps, only execute setting up and finishing of script.")
	parser.add_argument("targetname", nargs="?", help="output folder name for the generated snapshots.")
	parser.add_argument("savename", nargs="*", help="Names of the savegames to generate snapshots from. If no savegames are provided the latest save or the save matching outfolder will be gerated. Glob patterns are supported.")
	parser.add_argument("--force-lib-update", action="store_true", help="Forces an update of the web dependencies.")
	parser.add_argument('--temp-dir', '--tempdir', type=lambda p: Path(p).resolve(), help='Set a custom temporary directory to use (this is only needed if the defualt one is on a RAM disk, which Factorio does not support).')

	args = parser.parse_args()
	if args.verbose > 0:
		print(args)

	if args.update:
		checkUpdate(args.reverseupdatetest)

	saves = Path(userFolder, "saves")
	if args.targetname:
		foldername = args.targetname
	else:
		timestamp, filePath = max(
			(save.stat().st_mtime, save)
			for save in saves.iterdir()
			if not save.stem.startswith("_autosave")
		)
		foldername = filePath.stem
		print("No save name passed. Using most recent save: %s" % foldername)
	saveNames = args.savename or [foldername]
	foldername = foldername.replace('*', '').replace('?', '')

	saveGames = set()
	for saveName in saveNames:
		saveNameEscaped = glob.escape(saveName).replace("[*]", "*")
		globResults = list(saves.glob(saveNameEscaped))
		globResults += list(saves.glob(f"{saveNameEscaped}.zip"))

		if not globResults:
			print(f'Cannot find savefile: "{saveName}"')
			raise IOError(f"savefile {saveName!r} not found in {str(saves)!r}")
		results = [save for save in globResults if save.is_file()]
		for result in results:
			saveGames.add(result.stem)

	saveGames = naturalSort(list(saveGames))

	if args.verbose > 0:
		print(f"Will generate snapshots for : {saveGames}")

	if args.factorio:
		possibleFactorioPaths = [args.factorio]
	else:
		unixPaths = [
			"../../bin/x64/factorio.exe",
			"../../bin/x64/factorio",
		]
		windowsPathsStandalone = [
			"Program Files/Factorio/bin/x64/factorio.exe",
			"Games/Factorio/bin/x64/factorio.exe",
		]
		windowsPathsSteam = [
			"Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe",
			"Steam/steamapps/common/Factorio/bin/x64/factorio.exe",
		]
		availableDrives = [
			"%s:/" % d for d in string.ascii_uppercase if Path(f"{d}:/").exists()
		]
		possibleFactorioPaths = unixPaths
		if args.steam == 0:
			possibleFactorioPaths += [ drive + path for drive in availableDrives for path in windowsPathsStandalone ]
		if args.standalone == 0:
			possibleFactorioPaths += [ drive + path for drive in availableDrives for path in windowsPathsSteam ]

	try:
		factorioPath = next(
			x
			for x in map(Path, possibleFactorioPaths)
			if x.is_file()
		)
	except StopIteration:
		raise Exception(
			"Can't find factorio.exe. Please pass --factorio=PATH as an argument.",
			"Searched the following locations:", possibleFactorioPaths
		)

	print("factorio path: {}".format(factorioPath))

	psutil.Process(os.getpid()).nice(psutil.ABOVE_NORMAL_PRIORITY_CLASS if os.name == 'nt' else 5)

	workthread = None

	workfolder = Path(args.basepath, foldername).resolve()
	try:
		print("output folder: {}".format(workfolder.relative_to(Path(userFolder))))
	except ValueError:
		print("output folder: {}".format(workfolder.resolve()))

	try:
		workfolder.mkdir(parents=True, exist_ok=True)
	except FileExistsError:
		raise Exception(f"{workfolder} exists and is not a directory!")

	updateLib(args.force_lib_update)

	#TODO: integrity check, if done files aren't there or there are any bmps left, complain.

	if args.mod_path.resolve() != Path(userFolder,"mods").resolve():
		linkCustomModFolder(args.mod_path)

	changeModlist(args.mod_path, True)

	manager = mp.Manager()
	rawTags = manager.dict()
	rawTags["__used"] = False

	if args.delete:
		print(f"Deleting output folder ({workfolder})")
		try:
			rmtree(workfolder)
		except (FileNotFoundError, NotADirectoryError):
			pass


	###########################################
	#                                         #
	#              Start of Work              #
	#                                         #
	###########################################

	datapath = Path(workfolder, "latest.txt")

	isFirstSnapshot = True

	try:

		daytimes = []
		if args.day:
			daytimes.append("day")
		if args.night:
			daytimes.append("night")

		for index, savename in () if args.dry else enumerate(saveGames):
			for daytimeIndex, setDaytime in enumerate(daytimes):

				printErase("cleaning up")
				if datapath.is_file():
					datapath.unlink()

				buildAutorun(args, workfolder, foldername, isFirstSnapshot, setDaytime)
				isFirstSnapshot = False

				if args.temp_dir is not None:
					try:
						os.makedirs(args.temp_dir)
					except OSError:
						pass
				with TemporaryDirectory(prefix="FactorioMaps-", dir=args.temp_dir) as tmpDir:
					configPath = buildConfig(args, tmpDir, args.basepath)

					pid = None
					isSteam = None
					pidBlacklist = [p.info["pid"] for p in psutil.process_iter(attrs=['pid', 'name']) if p.info['name'] == "factorio.exe"]


					launchArgs = [
						'--load-game',
						str(Path(userFolder, 'saves', savename).absolute()),
						'--disable-audio',
						'--config',
						str(configPath),
						"--mod-directory",str(args.mod_path.absolute()),
						"--disable-migration-window"
					]

					usedSteamLaunchHack = False

					if os.name == "nt":
						steamApiPath = Path(factorioPath, "..", "steam_api64.dll")
					else:
						steamApiPath = Path(factorioPath, "..", "steam_api64.so")

					if steamApiPath.exists():	# chances are this is a steam install..
						# try to find steam
						try:
							from winreg import OpenKey, HKEY_CURRENT_USER, ConnectRegistry, QueryValueEx, REG_SZ

							key = OpenKey(ConnectRegistry(None, HKEY_CURRENT_USER), r'Software\Valve\Steam')
							val, valType = QueryValueEx(key, 'SteamExe')
							if valType != REG_SZ:
								raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), "SteamExe")
							steamPath = Path(val)
						except (ImportError, FileNotFoundError) as e:
							# fallback to old method
							if os.name == "nt":
								steamPath = Path(factorioPath, "..", "..", "..", "..", "..", "..", "steam.exe")
							else:
								steamPath = Path(factorioPath, "..", "..", "..", "..", "..", "..", "steam")

						if steamPath and steamPath.exists(): # found a steam executable
							usedSteamLaunchHack = True
							exeWithArgs = [
								str(steamPath),
								"-applaunch",
								"427520"
							] + launchArgs

					if not usedSteamLaunchHack:	# if non steam factorio, or if steam factorio but steam executable isnt found.
						exeWithArgs = [
							str(factorioPath)
						] + launchArgs

					if args.verbose:
						printErase(exeWithArgs)

					condition = mp.Condition()
					results = manager.list()

					printErase("starting factorio")
					startLogProcess = mp.Process(
						target=startGameAndReadGameLogs,
						args=(results, condition, exeWithArgs, usedSteamLaunchHack, tmpDir, pidBlacklist, rawTags, args)
					)
					startLogProcess.daemon = True
					startLogProcess.start()

					with condition:
						condition.wait()
					isSteam, pid = results[:]

					if isSteam is None:
						raise Exception("isSteam error")
					if pid is None:
						raise Exception("pid error")

					while not datapath.exists():
						time.sleep(0.4)

					# empty autorun.lua
					Path(__file__, "..", "autorun.lua").resolve().open('w', encoding="utf-8").close()

					latest = []
					with datapath.open('r', encoding="utf-8") as f:
						for line in f:
							latest.append(line.rstrip("\n"))
					if args.verbose:
						printErase(latest)

					firstOutFolder, timestamp, surface, daytime = latest[-1].split(" ")
					firstOutFolder = firstOutFolder.replace("/", " ")
					waitfilename = Path(args.basepath, firstOutFolder, "images", timestamp, surface, daytime, "done.txt")

					isKilled = [False]
					def waitKill(isKilled, pid):
						while not isKilled[0]:
							#print(f"Can I kill yet? {os.path.isfile(waitfilename)} {waitfilename}")
							if os.path.isfile(waitfilename):
								isKilled[0] = True
								kill(pid)
								break
							else:
								time.sleep(0.4)

					killThread = threading.Thread(target=waitKill, args=(isKilled, pid))
					killThread.daemon = True
					killThread.start()

					if workthread and workthread.is_alive():
						#print("waiting for workthread")
						workthread.join()

					timestamp = None
					daytimeSurfaces = {}
					for jindex, screenshot in enumerate(latest):
						outFolder, timestamp, surface, daytime = list(map(lambda s: s.replace("|", " "), screenshot.split(" ")))
						outFolder = outFolder.replace("/", " ")
						print(f"Processing {outFolder}/{'/'.join([timestamp, surface, daytime])} ({len(latest) * index + jindex + 1 + daytimeIndex} of {len(latest) * len(saveGames) * len(daytimes)})")

						if daytime in daytimeSurfaces:
							daytimeSurfaces[daytime].append(surface)
						else:
							daytimeSurfaces[daytime] = [surface]

						#print("Cropping %s images" % screenshot)
						crop(outFolder, timestamp, surface, daytime, args.basepath, args)
						waitlocalfilename = os.path.join(args.basepath, outFolder, "Images", timestamp, surface, daytime, "done.txt")
						if not os.path.exists(waitlocalfilename):
							#print("waiting for done.txt")
							while not os.path.exists(waitlocalfilename):
								time.sleep(0.4)



						def refZoom():
							needsThumbnail = index + 1 == len(saveGames)
							#print("Crossreferencing %s images" % screenshot)
							ref(outFolder, timestamp, surface, daytime, args.basepath, args)
							#print("downsampling %s images" % screenshot)
							zoom(outFolder, timestamp, surface, daytime, args.basepath, needsThumbnail, args)

							if jindex == len(latest) - 1:
								print("zooming renderboxes", timestamp)
								zoomRenderboxes(daytimeSurfaces, workfolder, timestamp, Path(args.basepath, firstOutFolder, "Images"), args)

						if screenshot != latest[-1]:
							refZoom()
						else:
							startLogProcess.terminate()

							if not isKilled[0]:
								isKilled[0] = True
								kill(pid)

							if savename == saveGames[-1] and daytimeIndex == len(daytimes) - 1:
								refZoom()

							else:
								workthread = threading.Thread(target=refZoom)
								workthread.daemon = True
								workthread.start()









		if os.path.isfile(os.path.join(workfolder, "mapInfo.out.json")):
			print("generating mapInfo.json")
			with Path(workfolder, "mapInfo.json").open('r+', encoding='utf-8') as destf, Path(workfolder, "mapInfo.out.json").open("r", encoding='utf-8') as srcf:
				data = json.load(destf)
				for mapIndex, mapStuff in json.load(srcf)["maps"].items():
					for surfaceName, surfaceStuff in mapStuff["surfaces"].items():
						if "chunks" in surfaceStuff:
							data["maps"][int(mapIndex)]["surfaces"][surfaceName]["chunks"] = surfaceStuff["chunks"]
						if "links" in surfaceStuff:
							for linkIndex, link in enumerate(surfaceStuff["links"]):
								data["maps"][int(mapIndex)]["surfaces"][surfaceName]["links"][linkIndex]["path"] = link["path"]
								data["maps"][int(mapIndex)]["surfaces"][surfaceName]["links"][linkIndex]["zoom"]["min"] = link["zoom"]["min"]
				destf.seek(0)
				json.dump(data, destf)
				destf.truncate()
			os.remove(os.path.join(workfolder, "mapInfo.out.json"))


		modVersions = sorted(
				map(lambda m: (m.group(2).lower(), (m.group(3), m.group(4), m.group(5), m.group(6) is None), m.group(1)),
					filter(lambda m: m,
						map(lambda f: re.search(r"^((.*)_(\d+)\.(\d+)\.(\d+))(\.zip)?$", f, flags=re.IGNORECASE),
							os.listdir(os.path.join(args.basepath, args.mod_path))))),
				key = lambda t: t[1],
				reverse = True)


		rawTags["__used"] = True
		if args.tags:
			print("updating labels")
			tags = {}
			def addTag(tags, itemType, itemName, force=False):
				index = itemType + itemName[0].upper() + itemName[1:]
				if index in rawTags:
					tags[index] = {
						"itemType": itemType,
						"itemName": itemName,
						"iconPath": "Images/labels/" + itemType + "/" + itemName + ".png",
					}
				else:
					if force:
						raise "tag not found."
					else:
						print(f"[WARNING] tag \"{index}\" not found.")
			with Path(workfolder, "mapInfo.json").open('r+', encoding='utf-8') as mapInfoJson:
				data = json.load(mapInfoJson)
				for mapStuff in data["maps"]:
					for surfaceName, surfaceStuff in mapStuff["surfaces"].items():
						if "tags" in surfaceStuff:
							for tag in surfaceStuff["tags"]:
								if "iconType" in tag:
									addTag(tags, tag["iconType"], tag["iconName"], True)
								if "text" in tag:
									for match in re.finditer("\[([^=]+)=([^\]]+)", tag["text"]):
										addTag(tags, match.group(1), match.group(2))

			rmtree(os.path.join(workfolder, "Images", "labels"), ignore_errors=True)

			for tagIndex, tag in tags.items():
				dest = os.path.join(workfolder, tag["iconPath"])
				os.makedirs(os.path.dirname(dest), exist_ok=True)

				rawPath = rawTags[tagIndex]

				icons = rawPath.split('|')
				img = None
				for i, path in enumerate(icons):
					m = re.match(r"^__([^\/]+)__[\/\\](.*)$", path)
					if m is None:
						raise Exception("raw path of %s %s: %s not found" % (tag["iconType"], tag["iconName"], path))

					iconColor = m.group(2).split("?")
					icon = iconColor[0]
					if m.group(1) in ("base", "core"):
						src = os.path.join(os.path.split(factorioPath)[0], "../../data", m.group(1), icon + ".png")
					else:
						mod = next(mod for mod in modVersions if mod[0] == m.group(1).lower())
						if not mod[1][3]: #true if mod is zip
							zipPath = os.path.join(args.basepath, args.mod_path, mod[2] + ".zip")
							with ZipFile(zipPath, 'r') as zipObj:
								if len(icons) == 1:
									zipInfo = zipObj.getinfo(os.path.join(mod[2], icon + ".png").replace('\\', '/'))
									zipInfo.filename = os.path.basename(dest)
									zipObj.extract(zipInfo, os.path.dirname(os.path.realpath(dest)))
									src = None
								else:
									src = zipObj.extract(os.path.join(mod[2], icon + ".png").replace('\\', '/'), os.path.join(tempfile.gettempdir(), "FactorioMaps"))
						else:
							src = os.path.join(args.basepath, args.mod_path, mod[2], icon + ".png")

					if len(icons) == 1:
						if src is not None:
							img = Image.open(src)
							w, h = img.size
							img = img.crop((0, 0, h, h)).resize((64, 64))
							img.save(dest)
					else:
						newImg = Image.open(src)
						w, h = newImg.size
						newImg = newImg.crop((0, 0, h, h)).resize((64, 64)).convert("RGBA")
						if len(iconColor) > 1:
							newImg = ImageChops.multiply(newImg, Image.new("RGBA", newImg.size, color=tuple(map(lambda s: int(round(float(s))), iconColor[1].split("%")))))
						if i == 0:
							img = newImg
						else:
							img.paste(newImg.convert("RGB"), (0, 0), newImg)
				if len(icons) > 1:
					img.save(dest)



		print("applying configuration")
		with Path(workfolder, "mapInfo.json").open("r+", encoding='utf-8') as f:
			mapInfo = json.load(f)
			if args.default_timestamp != None or "defaultTimestamp" not in mapInfo["options"]:
				if args.default_timestamp == None:
					args.default_timestamp = -1
				mapInfo["options"]["defaultTimestamp"] = args.default_timestamp
				f.seek(0)
				json.dump(mapInfo, f)
				f.truncate()



		print("generating mapInfo.js")
		with Path(workfolder, "mapInfo.js").open('w', encoding="utf-8") as outf, Path(workfolder, "mapInfo.json").open("r", encoding='utf-8') as inf:
			outf.write('"use strict";\nwindow.mapInfo = JSON.parse(')
			outf.write(json.dumps(inf.read()))
			outf.write(");")


		print("creating index.html")
		for fileName in ("index.html", "index.css", "index.js"):
			copy(Path(__file__, "..", "web", fileName).resolve(), os.path.join(workfolder, fileName))
		try:
			rmtree(os.path.join(workfolder, "lib"))
		except (FileNotFoundError, NotADirectoryError):
			pass
		copytree(Path(__file__, "..", "web", "lib").resolve(), os.path.join(workfolder, "lib"))


	finally:
		if pid:
			kill(pid)
		changeModlist(args.mod_path, False)

if __name__ == '__main__':
	auto(*sys.argv[1:])
