#!/usr/bin/env python3
"""Structural preflight. This does not replace xcodebuild or Simulator tests."""
import json
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from generate_project import ROOT, project, render, scheme

data = project()
objects = data["objects"]
errors = []


def require(test, message):
    if not test:
        errors.append(message)


project_path = ROOT / "WeatherApp.xcodeproj/project.pbxproj"
require(project_path.read_text() == "// !$*UTF8*$!\n" + render(data) + "\n",
        "Project file is out of date; run python3 scripts/generate_project.py.")
scheme_path = ROOT / "WeatherApp.xcodeproj/xcshareddata/xcschemes/WeatherApp.xcscheme"
require(scheme_path.read_text() == scheme(), "Shared scheme differs from the generator.")
ET.parse(scheme_path)
for ref, obj in objects.items():
    require(bool(re.fullmatch(r"[A-F0-9]{24}", ref)), f"Invalid object ID {ref}")
    if obj["isa"] == "PBXFileReference" and obj["sourceTree"] == "<group>":
        require((ROOT / obj["path"]).exists(), f"Missing file: {obj['path']}")
    for key in ["fileRef", "target", "targetProxy", "mainGroup", "productReference", "buildConfigurationList", "baseConfigurationReference"]:
        if key in obj:
            require(obj[key] in objects, f"Broken {key} in {ref}")
    for key in ["children", "files", "targets", "buildPhases", "dependencies", "buildConfigurations"]:
        for child in obj.get(key, []):
            require(child in objects, f"Broken {key} reference in {ref}: {child}")

for path in list(ROOT.rglob("*.plist")) + list(ROOT.rglob("*.entitlements")) + list(ROOT.rglob("*.xcprivacy")):
    plistlib.loads(path.read_bytes())
for path in list(ROOT.rglob("Contents.json")) + list(ROOT.rglob("*.xcstrings")):
    json.loads(path.read_text())
catalog = json.loads((ROOT / "Shared/Resources/Localizable.xcstrings").read_text())["strings"]
for key, value in catalog.items():
    require(all(lang in value["localizations"] for lang in ["pt-BR", "en"]), f"Missing translation: {key}")
for path in ROOT.rglob("*.swift"):
    text = path.read_text()
    for key in re.findall(r'L10n\.(?:text|format)\("([^"]+)"', text):
        require(key in catalog or key in ["condition.", "unit."], f"Missing string {key} in {path.name}")
    if path.name != "PreviewWeather.swift" and not path.name.endswith("Tests.swift") and path.name != "WeatherPreviews.swift":
        require("PreviewWeather" not in text, f"Preview fixture referenced in runtime file {path.name}")

app_entitlements = plistlib.loads((ROOT / "WeatherApp/WeatherApp.entitlements").read_bytes())
widget_entitlements = plistlib.loads((ROOT / "WeatherWidgets/WeatherWidgets.entitlements").read_bytes())
require(app_entitlements == widget_entitlements, "App and widget capabilities disagree.")
require(app_entitlements.get("com.apple.developer.weatherkit") is True, "WeatherKit entitlement missing.")
require(app_entitlements.get("com.apple.security.application-groups") == ["$(APP_GROUP_IDENTIFIER)"], "App Group mismatch.")
targets = [v for v in objects.values() if v["isa"] == "PBXNativeTarget"]
require({v["name"] for v in targets} == {"WeatherApp", "WeatherWidgets", "WeatherAppTests"}, "Required target missing.")
app = next(v for v in targets if v["name"] == "WeatherApp")
require(any(objects[phase]["isa"] == "PBXCopyFilesBuildPhase" for phase in app["buildPhases"]), "Widget embed phase missing.")
test_config = next(v for v in objects.values() if v["isa"] == "PBXNativeTarget" and v["name"] == "WeatherAppTests")
require(bool(test_config["dependencies"]), "Hosted tests must depend on the app.")
if sys.platform == "darwin":
    subprocess.run(["plutil", "-lint", str(project_path)], check=True)

if errors:
    raise SystemExit("\n".join(errors))
print(f"Structural validation passed: {len(targets)} targets, {len(objects)} project objects, {len(catalog)} localized strings.")
print("Swift compilation and test execution still require the iOS Build workflow or Xcode.")
