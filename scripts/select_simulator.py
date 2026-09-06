#!/usr/bin/env python3
"""Select an available iOS >=17 iPhone from the active Xcode runtime list."""
import json
import os
import re
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
choices = []
for runtime, devices in data["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    if not match or int(match[1]) < 17:
        continue
    version = tuple(int(part or 0) for part in match.groups())
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            choices.append((version, device["name"], device["udid"]))
if not choices:
    raise SystemExit("No available iOS >=17 iPhone simulator in the active Xcode installation.")
version, name, udid = max(choices)
print(f"Using {name}, iOS {'.'.join(map(str, version))}: {udid}")
if output := os.environ.get("GITHUB_OUTPUT"):
    with open(output, "a", encoding="utf-8") as stream:
        stream.write(f"udid={udid}\n")
