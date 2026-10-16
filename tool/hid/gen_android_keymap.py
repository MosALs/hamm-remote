#!/usr/bin/env python3
"""Generate test/fixtures/hid_android11_keymap.json.

Android turns a Bluetooth keyboard's HID usages into key codes in two steps:
the Linux kernel's hid-input driver maps a usage to a Linux key code, then
Android's Generic.kl maps that to an Android key code. This script reads both
real sources and writes the combined table, so the tests can prove each key
the app sends over Bluetooth arrives on the TV (Android 11) as intended.

  python3 tool/hid/gen_android_keymap.py --linux <linux checkout> --android <frameworks/base checkout>

Without paths it fetches the two files with sparse git clones (torvalds/linux
and LineageOS/android_frameworks_base, branch lineage-18.1 = Android 11).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "test", "fixtures", "hid_android11_keymap.json")


def sparse_clone(url: str, branch: str | None, paths: list[str], dest: str) -> None:
    cmd = ["git", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse"]
    if branch:
        cmd += ["-b", branch]
    subprocess.run(cmd + [url, dest], check=True)
    subprocess.run(["git", "-C", dest, "sparse-checkout", "set", "--no-cone", *paths], check=True)


def linux_tables(root: str) -> tuple[dict[int, str], dict[int, str], dict[str, int]]:
    hid = open(os.path.join(root, "drivers/hid/hid-input.c")).read()
    codes = open(os.path.join(root, "include/uapi/linux/input-event-codes.h")).read()

    names: dict[str, int] = {}
    for m in re.finditer(r"#define\s+((?:KEY|BTN)_\w+)\s+(0x[0-9a-fA-F]+|\d+)\b", codes):
        names[m.group(1)] = int(m.group(2), 0)
    for m in re.finditer(r"#define\s+((?:KEY|BTN)_\w+)\s+((?:KEY|BTN)_\w+)\s*$", codes, re.M):
        if m.group(2) in names:
            names[m.group(1)] = names[m.group(2)]
    by_number = {v: k for k, v in sorted(names.items(), key=lambda kv: kv[0], reverse=True)}

    # Keyboard page: the hid_keyboard[] table, indexed by usage.
    table = re.search(r"hid_keyboard\[256\]\s*=\s*\{(.*?)\};", hid, re.S).group(1)
    numbers = [int(x, 0) for x in re.findall(r"0x[0-9a-fA-F]+|\d+", table)]
    keyboard = {usage: by_number.get(code, str(code)) for usage, code in enumerate(numbers) if code}

    # Consumer page: the switch under HID_UP_CONSUMER (first mapping wins).
    start = hid.index("case HID_UP_CONSUMER:")
    end = hid.index("case HID_UP_HPVENDOR", start)
    consumer: dict[int, str] = {}
    for m in re.finditer(r"case (0x[0-9a-f]+):\s*map_key_clear\((\w+)\)", hid[start:end]):
        consumer.setdefault(int(m.group(1), 16), m.group(2))
    return keyboard, consumer, names


def android_layout(root: str) -> dict[int, str]:
    kl = open(os.path.join(root, "data/keyboards/Generic.kl")).read()
    return {int(m.group(1)): m.group(2) for m in re.finditer(r"^key\s+(\d+)\s+(\w+)", kl, re.M)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--linux")
    parser.add_argument("--android")
    args = parser.parse_args()
    tmp = tempfile.mkdtemp()
    linux = args.linux or os.path.join(tmp, "linux")
    android = args.android or os.path.join(tmp, "fwb")
    if not args.linux:
        sparse_clone("https://github.com/torvalds/linux.git", None,
                     ["/drivers/hid/hid-input.c", "/include/uapi/linux/input-event-codes.h"], linux)
    if not args.android:
        sparse_clone("https://github.com/LineageOS/android_frameworks_base.git", "lineage-18.1",
                     ["/data/keyboards/Generic.kl"], android)

    keyboard, consumer, names = linux_tables(linux)
    layout = android_layout(android)

    def android_key(linux_key: str) -> str | None:
        return layout.get(names.get(linux_key, -1))

    result = {
        "_source": "Linux drivers/hid/hid-input.c + Android 11 (lineage-18.1) data/keyboards/Generic.kl",
        "keyboard": {f"0x{u:02x}": android_key(k) for u, k in sorted(keyboard.items()) if android_key(k)},
        "consumer": {f"0x{u:03x}": android_key(k) for u, k in sorted(consumer.items()) if android_key(k)},
    }
    with open(OUT, "w") as f:
        json.dump(result, f, indent=1, sort_keys=False)
        f.write("\n")
    print(f"wrote {os.path.relpath(OUT)}: {len(result['keyboard'])} keyboard, {len(result['consumer'])} consumer usages")


if __name__ == "__main__":
    main()
