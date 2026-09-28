#!/bin/bash
set -euo pipefail
umask 077

for required in CERTIFICATE_BASE64 CERTIFICATE_PASSWORD PROFILE_BASE64 ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY; do
  if [[ -z "${!required:-}" ]]; then
    echo "::error::Missing signing setting: $required. See docs/TESTFLIGHT.md."
    exit 1
  fi
done
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid app version'; exit 1; }
[[ "$APP_BUILD" =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Build number must be 1–9999'; exit 1; }

printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/distribution.p12"
printf '%s' "$PROFILE_BASE64" | base64 --decode > "$RUNNER_TEMP/profile.mobileprovision"
printf '%s' "$ASC_PRIVATE_KEY" > "$RUNNER_TEMP/AuthKey.p8"
security cms -D -i "$RUNNER_TEMP/profile.mobileprovision" > "$RUNNER_TEMP/profile.plist"

python3 - <<'PY'
import datetime
import os
import plistlib
from pathlib import Path

temp = Path(os.environ['RUNNER_TEMP'])
with (temp / 'profile.plist').open('rb') as stream:
    profile = plistlib.load(stream)
team = os.environ['APPLE_TEAM_ID']
bundle = os.environ['BUNDLE_ID']
entitlements = profile['Entitlements']
assert team in profile['TeamIdentifier'], 'Wrong signing team'
assert entitlements['application-identifier'].endswith('.' + bundle), 'Wrong app profile'
assert not entitlements.get('get-task-allow', False), 'Development profile cannot go to TestFlight'
assert not profile.get('ProvisionedDevices'), 'Ad hoc profile cannot go to TestFlight'
assert not profile.get('ProvisionsAllDevices', False), 'Enterprise profile cannot go to TestFlight'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
uuid = profile['UUID']
with open(os.environ['GITHUB_ENV'], 'a') as stream:
    stream.write(f'PROFILE_UUID={uuid}\n')
with (temp / 'ExportOptions.plist').open('wb') as stream:
    plistlib.dump({
        'method': 'app-store-connect', 'destination': 'upload',
        'teamID': team, 'signingStyle': 'manual',
        'signingCertificate': 'Apple Distribution',
        'provisioningProfiles': {bundle: uuid},
        'manageAppVersionAndBuildNumber': False,
        # Allow this upload to be selected for App Review as well as TestFlight.
        # Uploading alone does not submit or release the app.
        'testFlightInternalTestingOnly': False,
        'uploadSymbols': True,
    }, stream)
PY

profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$RUNNER_TEMP/profile.plist")
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$RUNNER_TEMP/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
keychain_path="$RUNNER_TEMP/rebusrush-signing.keychain-db"
keychain_password=$(openssl rand -hex 32)
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$RUNNER_TEMP/distribution.p12" -P "$CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path"
