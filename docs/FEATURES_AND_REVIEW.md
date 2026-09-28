# Player features and private puzzle review

The September 2026 update adds:

- Regular selection prioritizes every remaining unsolved puzzle before filling spare slots with solved puzzles. Existing daily selections stay stable.
- **New this week** opens generated puzzles published during the previous seven days. Solves and hint purchases share regular-play progress, so switching screens never pays a second reward.
- Difficulty appears when recorded; old puzzles keep no label until reviewed.
- Every puzzle has a report button for answer, hint, or image problems. Reporting pauses a running timer challenge. Reports are private and can only be created by the signed-in player.
- **Settings → Save progress / Account** offers optional Apple sign-in. Linking a new Apple identity preserves the anonymous Firebase UID, coins, streaks and progress. An Apple identity with an existing game requires explicit confirmation before restoring it; guest progress is not merged. No name/email scope is requested.
- Account deletion reauthenticates with Apple, revokes Apple authorization through Firebase, removes the player's Firestore data and reports, then deletes the Firebase identity. The callable requires Firebase Authentication, recent sign-in, and App Check.
- Remote Config parameter `answer_model_name` controls Firebase AI Logic. The bundled default is `gemini-3.5-flash`. Fetching runs independently of sign-in with a ten-second timeout and one-hour minimum interval. Cached/default settings work offline; malformed parameter strings fall back to the bundled model. Test model availability and answer accuracy before publishing a new value. Transport/model errors do not consume an attempt.

## Private review dashboard

From the repository in PowerShell:

```powershell
./scripts/start-puzzle-review.ps1
```

Open the local URL printed in the terminal. Leave that terminal running; Ctrl+C stops the server. The tool uses the existing official Firebase CLI login. If needed, first run `npx --yes firebase-tools@15.31.0 login`. It targets only `puzzle-time-72ad9`. Alternatively, run `npm run puzzles:review --prefix functions` with Google Application Default Credentials. `FIREBASE_CLI_ROOT` can point at an installed `firebase-tools` package; `ADMIN_PORT` selects another local port.

The dashboard binds only to `127.0.0.1` and requires a random per-process session token. Google credentials stay on the server. Host and Origin checks reject cross-site requests. Never host this dashboard publicly or share its session URL.

Search by answer, puzzle ID, or batch date; filter active, retired or reported puzzles. Edit answers, three hints, explanations, difficulty, and the Firebase image URL. Save writes immediately and checks the document revision to prevent overwriting another editor's changes. `puzzleReviewAudit` retains the previous puzzle content. Reports can be resolved/reopened separately. The screen loads the latest 500 reports and states when that limit is reached.

Retirement is a reversible flag. Updated apps exclude retired puzzles from new selections while preserving existing saved regular/timer games and started daily challenges. The current Store release predates this flag and needs the app update to respect retirement.

## Firebase access

The deployed rules remove the November expiry and all public content writes. Puzzle artwork/content and daily configuration stay readable for compatibility. Player documents and the four known progress subcollections require the matching Firebase UID. Contact submissions and reports validate the signed-in author and allowed fields. Reports, audit history, generation runs and job controls cannot be read by players. Editing content requires server IAM, including the locally authenticated review tool.

This closes cross-player access and public writes. Coin and streak calculations still run on the client in existing releases; ownership rules are not an anti-cheat system. A future economy migration would move rewards and purchases to server-authoritative operations.

## Validation

`npm test --prefix functions` covers generation, review input/host protection, and account deletion ordering/auth freshness. The iOS build workflow compiles iPhone Release and simulator targets and runs the gameplay unit suite. On-device TestFlight checks still need to exercise Apple linking, restoration, deletion, App Check, rewarded ads, and weekly gameplay.

### TestFlight walkthrough

1. Open **New this week**, buy a hint and solve a puzzle. Opening that puzzle in regular play should retain the hint and solved state without a second reward.
2. Open the report form during a timer challenge. The timer should pause while the form is open and resume when it closes. Submit a real issue and check that it appears in the private review dashboard.
3. In **Settings → Save progress**, connect Apple and confirm that your existing coins and progress remain. Restart the app and confirm they still load.
4. On a second device or a fresh guest session, connect the same Apple account. Confirm the restore prompt explains that the current guest progress will be replaced, then verify the saved game loads.
5. Exercise account deletion only with a disposable test account: confirm with Apple, verify a fresh guest session starts, and check the deleted account's data is gone.
6. Test rewarded ads on the phone and verify that each completed ad awards coins once. Confirm a failed AI request leaves the attempt count unchanged.

Run the 174 non-mutating security checks against Google's Rules testing API with:

```powershell
npx --yes --package=firebase-tools@15.31.0 -c "node functions/scripts/check-security-rules.js"
```

References: [Firebase Apple authentication](https://firebase.google.com/docs/auth/ios/apple), [Firebase Remote Config for Apple platforms](https://firebase.google.com/docs/remote-config/ios/get-started).
