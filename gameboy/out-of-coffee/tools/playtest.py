#!/usr/bin/env python3
"""Play Out of Coffee start to finish headless (PyBoy) and check the story state.

usage: python tools/playtest.py [outdir]   - saves screenshots of the key moments
John is moved by writing his position (from build/coffee.sym), then walks
through doors and presses A like a player would.
"""
import re
import sys
from pathlib import Path
from pyboy import PyBoy

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "playtest"
OUT.mkdir(parents=True, exist_ok=True)
SYM = {}
for line in open(ROOT / "build" / "coffee.sym"):
    m = re.match(r"^[0-9a-f]+:([0-9a-f]+) (\w+)$", line.strip())
    if m:
        SYM[m.group(2)] = int(m.group(1), 16)
VARS = re.search(r"; variables: (.*)", (ROOT / "src/gen/things.asm").read_text()).group(1)
VARS = [v.split()[1] for v in VARS.split(", ")]

pb = PyBoy(str(ROOT / "build" / "coffee.gb"), window="null")
pb.set_emulation_speed(0)
mem = pb.memory


def hold(key, n):
    pb.button_press(key)
    pb.tick(n, True)
    pb.button_release(key)
    pb.tick(1, True)


def place(x, y):
    mem[SYM["wX"]], mem[SYM["wY"]] = x, y
    pb.tick(1, True)


def exit_room(side):
    x, y, key = {"e": (144, 60, "right"), "w": (0, 60, "left"),
                 "s": (72, 112, "down"), "n": (72, 0, "up")}[side]
    place(x, y)
    hold(key, 3)


def talk(x, y, face, shot_after=None, shot_every=False):
    place(x, y)
    hold(face, 2)
    hold("a", 1)
    for i in range(40):
        pb.tick(70, True)
        if shot_every:
            shot(f"{shot_every}_{i}")
        if not mem[SYM["wTalking"]]:
            break
        hold("a", 1)
    pb.tick(10, True)
    if shot_after:
        shot(shot_after)


def shot(name):
    pb.screen.image.convert("RGB").resize((480, 432), 0).save(OUT / f"{name}.png")


def state():
    return {n: mem[SYM["wVars"] + i] for i, n in enumerate(VARS)}


def check(step, **want):
    st = state()
    bad = {k: (st[k], v) for k, v in want.items() if st[k] != v}
    print(f"{'ok ' if not bad else 'BAD'} {step}: {st}" + (f"  wanted {bad}" if bad else ""))
    return not bad


pb.tick(200, True)
hold("start", 2)             # title screen
pb.tick(20, True)
ok = True
exit_room("e")                                        # corridor -> bridge
talk(76, 63, "up")                                    # Josef
ok &= check("Josef asks", asked=1, machine=0)
exit_room("w"); exit_room("s")                        # -> corridor -> galley
talk(6, 31, "up", shot_after="1_slapped")             # machine: wheeze + slap
ok &= check("slap", machine=1)
exit_room("w")                                        # -> hydroponics
talk(80, 71, "up", shot_after="2_beans")              # plant
ok &= check("beans", beans=1)
exit_room("e")                                        # -> galley
place(6, 31); hold("up", 2); hold("a", 1)
pb.tick(80, True); hold("a", 1); pb.tick(70, True); shot("3_rattle")
talk(6, 31, "up")
ok &= check("rattle", machine=2, beans=0)
exit_room("e"); exit_room("e")                        # -> cargo -> hangar
talk(128, 55, "up")                                   # Jimmie
ok &= check("wrench", wrench=1, helped=1)
exit_room("w")                                        # -> cargo
talk(64, 63, "up", shot_after="4_fuse")               # crate
ok &= check("fuse", fuse=1)
exit_room("w")                                        # -> galley
place(6, 31); hold("up", 2); hold("a", 1)
for i in range(3):
    pb.tick(80, True); hold("a", 1)
pb.tick(6, True); shot("5_boom_flash"); pb.tick(30, True); shot("5_boom_shake")
talk(6, 31, "up")
ok &= check("boom", machine=3, wrench=0, fuse=0)
exit_room("n"); exit_room("e")                        # -> corridor -> bridge
talk(76, 63, "up")                                    # Josef: tea
pb.tick(30, True)
shot("6_the_end")
ended = mem[SYM["wEnding"]] == 1
print("ok " if ended else "BAD", "the end screen" if ended else "no ending")
pb.stop(save=False)
sys.exit(0 if ok and ended else 1)
