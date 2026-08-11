import os
from pathlib import Path
from shutil import copytree, rmtree
from tempfile import TemporaryDirectory
from urllib.parse import urlparse
from urllib.request import build_opener, install_opener, urlretrieve

URLLIST = (
	"https://cdn.jsdelivr.net/npm/leaflet@1.6.0/dist/leaflet.css",
	"https://cdn.jsdelivr.net/npm/leaflet@1.6.0/dist/leaflet-src.min.js",
	"https://cdn.jsdelivr.net/npm/leaflet.fullscreen@1.4.5/Control.FullScreen.css",
	"https://cdn.jsdelivr.net/npm/leaflet.fullscreen@1.4.5/Control.FullScreen.min.js",
	"https://cdn.jsdelivr.net/npm/jquery@3.4.1/dist/jquery.min.js",
	"https://ajax.googleapis.com/ajax/libs/jqueryui/1.12.1/themes/smoothness/jquery-ui.css",
	"https://ajax.googleapis.com/ajax/libs/jqueryui/1.12.1/jquery-ui.min.js",
	"https://cdn.jsdelivr.net/gh/L0laapk3/Leaflet.OpacityControls@2/Control.Opacity.css",
	"https://cdn.jsdelivr.net/gh/L0laapk3/Leaflet.OpacityControls@2/Control.Opacity.js",
	"https://cdn.jsdelivr.net/npm/js-natural-sort@0.8.1/dist/naturalsort.min.js",
	"https://factorio.com/static/img/favicon.ico",
)


CURRENTVERSION = 4


def update(Force=True):

	targetPath = Path(__file__, "..", "web", "lib").resolve()

	if not Force:
		try:
			with open(Path(targetPath, "VERSION"), "r") as f:
				if f.readline() == str(CURRENTVERSION):
					return False
		except FileNotFoundError:
			pass

	with TemporaryDirectory() as tempDir:
		print(tempDir)

		opener = build_opener()
		opener.addheaders = [
			("User-agent", "Mozilla/5.0 U GUYS SUCK WHY ARE YOU BLOCKING Python-urllib")
		]
		install_opener(opener)

		for url in URLLIST:
			print(f"downloading {url}")
			urlretrieve(url, Path(tempDir, Path(urlparse(url).path).name))

		try:
			rmtree(targetPath)
		except (FileNotFoundError, NotADirectoryError):
			pass

		copytree(tempDir, targetPath)
		with open(Path(targetPath, "VERSION"), "w") as f:
			f.write(str(CURRENTVERSION))

		# the temporary directory is only readable by its owner, and copytree
		# carries that over. these are static web assets, they need to be readable.
		os.chmod(targetPath, 0o755)
		for entry in targetPath.iterdir():
			os.chmod(entry, 0o644)
			
		if __name__ == "__main__":
			input("Press Enter to continue...")
			
		return True


if __name__ == "__main__":
	update(True)
