#!/usr/bin/env python3
"""
swipe.py - tiny Mac-style touchpad swipe -> i3 workspace switcher.

Reads gesture events from `libinput debug-events` and runs i3-msg.
Needs: libinput-tools package, and your user in the `input` group.
"""
import re
import subprocess
import time

FINGERS = 3          # how many fingers the swipe needs
THRESHOLD = 50       # how far (in libinput units) you must swipe to trigger
SWIPE_LEFT_CMD = ["i3-msg", "-q", "workspace", "prev_on_output"]
SWIPE_RIGHT_CMD = ["i3-msg", "-q", "workspace", "next_on_output"]

# e.g. " event7  GESTURE_SWIPE_UPDATE  +1.234s  3 -12.50/ 0.30 (...)"
# (repeated events have an extra counter column before the time, e.g. "UPDATE  2  +0.120s")
LINE_RE = re.compile(r"(GESTURE_SWIPE_\w+)\s+(?:\d+\s+)?\+?[\d.]+s\s+(\d+)\s*(.*)")
DELTA_RE = re.compile(r"(-?\d+\.\d+)/\s*(-?\d+\.\d+)")


def run():
    proc = subprocess.Popen(
        ["stdbuf", "-oL", "libinput", "debug-events"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    dx = dy = 0.0
    for line in proc.stdout:
        m = LINE_RE.search(line)
        if not m:
            continue
        event, fingers, rest = m.group(1), int(m.group(2)), m.group(3)
        if fingers != FINGERS:
            continue

        if event == "GESTURE_SWIPE_BEGIN":
            dx = dy = 0.0
        elif event == "GESTURE_SWIPE_UPDATE":
            d = DELTA_RE.search(rest)
            if d:
                dx += float(d.group(1))
                dy += float(d.group(2))
        elif event == "GESTURE_SWIPE_END":
            if "cancelled" in rest:
                continue
            # only horizontal swipes, and only if long enough
            if abs(dx) > THRESHOLD and abs(dx) > abs(dy):
                subprocess.run(SWIPE_LEFT_CMD if dx < 0 else SWIPE_RIGHT_CMD)
    proc.wait()


if __name__ == "__main__":
    while True:          # restart if libinput ever exits (e.g. after suspend)
        run()
        time.sleep(2)
