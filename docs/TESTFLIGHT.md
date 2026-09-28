# TestFlight from Windows

GitHub Actions supplies the Mac and Xcode. The shared `PuzzleTime` scheme supports
both the manual **iOS build check** and **Upload to TestFlight** workflows.
The build check compiles the release and unit tests; it does not execute the app
or tests, or intentionally connect to Firebase.

## One-time signing setup

The uploader requires these repository Actions secrets (never commit their values):

| Secret | Value |
| --- | --- |
| `APPLE_DISTRIBUTION_P12_BASE64` | Base64-encoded Apple Distribution certificate with its private key (.p12) |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | Password protecting that .p12 |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 App Store profile for `com.FooWibble.puzzle-time`, team `YY4QZ9BB2G`, matching the certificate |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | Team API key issuer ID |
| `ASC_PRIVATE_KEY` | Downloaded .p8 private key, including its PEM header and footer |

Apple API access must first be enabled by the account holder. A Developer API key
can upload builds; managing testers/build information through the API needs more
access. Prefer managing this app's internal tester group through App Store Connect.
Team API keys apply across the organization's apps; review the role before creating
one. Existing signing certificates cannot be downloaded with their private keys:
export a matching .p12 from the original Mac, or create a dedicated signing identity
and profile. Never revoke an existing identity to make room without reviewing its use.

## Build and upload

1. Run **iOS build check** for the current `main` commit and resolve compiler errors.
2. Run **Upload to TestFlight** on `main`, choosing a version newer than the live app
   (default `1.1.1`) and a unique build number (default `2`). Reusing a processed
   version/build pair will fail; increment the build for the next upload.
3. The workflow validates the profile, installs it in a temporary runner keychain,
   archives Release, and uploads with **TestFlight internal testing only** enabled.
   It does not submit an App Store release or distribute to external testers.
4. Wait for Apple processing, then add the build to the existing `FooWibble` internal
   group and verify your Apple account is a tester. Install using TestFlight.

This app currently uses the production Firebase project. Installing a beta does
not isolate its data. Use a test player and avoid resetting important player data.
The existing gameplay review lists the device checks to perform.

## Setup status (2026-09-28)

- The iPhone Release build and simulator unit-test compilation passed in
  [the first Mac build check](https://github.com/peytonlwhite/RebusRush/actions/runs/36365926836).
- The approved Developer upload API key and dedicated distribution identity/profile
  are installed as the six repository secrets listed above. Signing material is
  excluded from Git. The dedicated profile expires in September 2027.
- Signed internal upload for version 1.1.1 (2) was started in
  [run 36366669092](https://github.com/peytonlwhite/RebusRush/actions/runs/36366669092).
  Starting the workflow is not confirmation of upload or TestFlight availability.

References: [GitHub signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[Apple build uploads](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds),
[internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
