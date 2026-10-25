#!/usr/bin/env python3
"""Static product-name audit. Run from the native checkout; no app or tests are launched."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
product_roots = ("iLightCraft/", "iLightCraftTests/", "iLightCraftUITests/", "iLightCraft.xcodeproj/", "Config/", "Engine/ffi/", "scripts/", "ci_scripts/")
# Compatibility is read-only and covered by saved migration tests. Legal texts stay verbatim.
exceptions = {"iLightCraft/Models/Engine/LegacyEditCompatibility.swift"}
pattern = re.compile("un" + "veil", re.I)
failures = []
# Check the shipping identity as well as spelling: a clean text scan alone can
# miss an accidentally reverted display name, scheme or bridge library.
try:
    project = (root / "iLightCraft.xcodeproj/project.pbxproj").read_text()
    with (root / "iLightCraft/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    for key in ("CFBundleName", "CFBundleDisplayName"):
        generated_values = re.findall(r"^\s*INFOPLIST_KEY_" + key + r"\s*=\s*([^;]+);", project, re.M)
        generated_name_is_valid = len(generated_values) == 2 and all(value.strip().strip('"') == "iLightCraft" for value in generated_values)
        if info.get(key) != "iLightCraft" and not (key not in info and generated_name_is_valid):
            failures.append(f"iLightCraft/Info.plist: {key} must be iLightCraft")
    with (root / "Engine/ffi/Cargo.toml").open("rb") as source:
        bridge = tomllib.load(source)
    if bridge.get("package", {}).get("name") != "ilightcraft-ffi" or bridge.get("lib", {}).get("name") != "ilightcraft_ffi":
        failures.append("Engine/ffi/Cargo.toml: unexpected bridge identity")
    scheme = ET.parse(root / "iLightCraft.xcodeproj/xcshareddata/xcschemes/iLightCraft.xcscheme")
    app_references = [ref for ref in scheme.iter("BuildableReference") if ref.get("BlueprintName") == "iLightCraft"]
    if not app_references or any(ref.get("BuildableName") != "iLightCraft.app" or ref.get("ReferencedContainer") != "container:iLightCraft.xcodeproj" for ref in app_references):
        failures.append("iLightCraft.xcscheme: unexpected app product or project")
    app_ids = re.findall(r"^\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);", project, re.M)
    if not app_ids or any(value.strip().strip('"') not in {"com.cwallyman.iLightCraft", "com.cwallyman.iLightCraft.tests", "com.cwallyman.iLightCraft.uitests"} for value in app_ids):
        failures.append("project.pbxproj: unexpected product bundle identifier")
except (OSError, ValueError, ET.ParseError) as error:
    failures.append(f"Could not verify shipping identity: {error}")
files = subprocess.check_output(["rg", "--files", "--hidden", "-g", "!.git/**"], cwd=root, text=True).splitlines()
for name in files:
    if not name.startswith(product_roots) or name in exceptions or name.startswith("iLightCraft/Resources/Legal/"):
        continue
    path = root / name
    if pattern.search(name):
        failures.append(name + ": old product name in path")
    try:
        text = path.read_text()
    except (UnicodeError, OSError):
        continue
    for number, line in enumerate(text.splitlines(), 1):
        if pattern.search(line):
            failures.append(f"{name}:{number}: unexpected old product name")
if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Brand audit passed: iLightCraft shipping identity verified; product source/config/scripts are clean outside read-only compatibility and legal notices.")
