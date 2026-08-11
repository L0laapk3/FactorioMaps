import sys
from shutil import get_terminal_size as tsize


class Progress:
    """Progress reporting for the crop, ref and zoom steps.

    On a terminal this draws the usual bar redrawn in place. When output is
    redirected (a log file, `docker logs`) carriage returns are useless and turn
    the whole run into one endless line, so it prints a plain line every few
    percent instead.
    """

    def __init__(self, label, stepPercent=5):
        self.label = label
        self.stepPercent = stepPercent
        self.lastPercent = -stepPercent
        self.interactive = sys.stdout.isatty()
        if self.interactive:
            print(f"{self.label} {0:5.1f}% [{' ' * (tsize()[0] - 15)}]", end="")
        else:
            print(f"{self.label} started", flush=True)

    def update(self, fraction):
        percent = fraction * 100
        if self.interactive:
            width = tsize()[0] - 15
            filled = int(fraction * width)
            print(f"\r{self.label} {round(percent, 1):5.1f}% [{'=' * filled}{' ' * (width - filled)}]", end="")
        elif percent >= self.lastPercent + self.stepPercent:
            self.lastPercent = percent - (percent % self.stepPercent)
            print(f"{self.label} {percent:5.1f}%", flush=True)

    def done(self):
        if self.interactive:
            print(f"\r{self.label} {100:5.1f}% [{'=' * (tsize()[0] - 15)}]")
        else:
            print(f"{self.label} 100.0% done", flush=True)
