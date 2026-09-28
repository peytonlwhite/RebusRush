"""Apply manual signing only to the app in the disposable CI checkout.

Passing a provisioning profile as an xcodebuild command-line build setting also
applies it to Swift Package resource bundles, which cannot use profiles.
"""
import json
import os
import subprocess
from pathlib import Path

project = Path("PuzzleTime.xcodeproj/project.pbxproj")
parsed = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(project)
]))
objects = parsed["objects"]
targets = [value for value in objects.values()
           if value.get("isa") == "PBXNativeTarget"
           and value.get("name") == "PuzzleTime"
           and value.get("productType") == "com.apple.product-type.application"]
assert len(targets) == 1, "Expected exactly one PuzzleTime app target"
config_list = objects[targets[0]["buildConfigurationList"]]
release_configs = [objects[key] for key in config_list["buildConfigurations"]
                   if objects[key]["name"] == "Release"]
assert len(release_configs) == 1, "Expected one app Release configuration"
settings = release_configs[0]["buildSettings"]
assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == os.environ["BUNDLE_ID"]
settings.update({
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Distribution",
    "DEVELOPMENT_TEAM": os.environ["APPLE_TEAM_ID"],
    "PROVISIONING_PROFILE_SPECIFIER": os.environ["PROFILE_UUID"],
})
temporary = Path(os.environ["RUNNER_TEMP"]) / "signed-project.json"
temporary.write_text(json.dumps(parsed))
subprocess.run(["plutil", "-convert", "xml1", "-o", str(project), str(temporary)], check=True)
print("Configured manual signing for PuzzleTime Release only.")
