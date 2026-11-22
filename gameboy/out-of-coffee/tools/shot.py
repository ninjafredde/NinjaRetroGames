#!/usr/bin/env python3
"""Play the ROM headless in PyBoy and save screenshots (for checking without a person).

usage: python tools/shot.py <rom> <outdir> <steps...>
steps:  60            run 60 frames
        right:30      hold Right for 30 frames (up down left right a b start select)
        up+left:20    hold several
        shot:name     save <outdir>/name.png (3x size)
"""
import sys
from pathlib import Path
from pyboy import PyBoy


def main():
    rom, outdir, steps = sys.argv[1], Path(sys.argv[2]), sys.argv[3:]
    outdir.mkdir(parents=True, exist_ok=True)
    pb = PyBoy(rom, window="null")
    pb.set_emulation_speed(0)
    for step in steps:
        if step.startswith("shot:"):
            img = pb.screen.image.convert("RGB")
            img = img.resize((img.width * 3, img.height * 3), 0)
            img.save(outdir / f"{step[5:]}.png")
            continue
        if ":" in step:
            keys, n = step.split(":")
            keys = keys.split("+")
            for k in keys:
                pb.button_press(k)
            pb.tick(int(n), True)
            for k in keys:
                pb.button_release(k)
            pb.tick(1, True)
        else:
            pb.tick(int(step), True)
    pb.stop(save=False)


if __name__ == "__main__":
    main()
