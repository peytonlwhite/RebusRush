# RebusRush gameplay review

Reviewed the SwiftUI client and its gameplay/persistence code on 2026-09-27.
Changes were prepared on `codex/fix-gameplay-progress` for publication to `main`.
No production records, rules, Storage assets, or deployed app versions were changed.

## Fixes implemented

| Feature | Problem | Change |
| --- | --- | --- |
| Daily puzzle | The configured puzzle was replaced with a random one when it was outside the player's five regular puzzles. | Fetch that puzzle directly by its Firestore ID. |
| Timer resume | Readers expected `riddle1Correct`, while saves use `riddleOneCorrect` (same mismatch for hints and attempts). | Read the production word-based fields, with numeric-key compatibility. Restore the saved puzzle IDs. |
| Hint retention | Temporarily hidden hints were saved as no longer purchased. | Preserve purchased indices from progress; merge server purchases when saving answers and timer progress. |
| Daily rewards | Daily attempts were counted using regular-mode progress. | Use the daily progress cache and committed attempt/hint counts. |
| Coins | Progress and rewards were separate writes; retries could also award already-solved puzzles again. | Commit progress and coins together in transactions; award only a transition to solved. |
| Streaks | Timer wins never called the streak updater; repeat daily wins incremented again; local midnight conflicted with UTC record dates. | Call the timer updater and calculate streaks transactionally using UTC days. New accounts no longer start with a fictitious last-solved timestamp. |
| Timer lifecycle | Four timer implementations had different pause behavior; leaving during a save could leave a timer alive. | Share one ticker, respect ads/background/pause state, and always invalidate it on exit. |
| Timer writes | Autosaves could overwrite purchased hints, solved flags, or a completed record. | Merge purchases and solved flags transactionally, and preserve completed records. |
| Hint purchasing | Repeated taps could initiate purchases; timer cache changed before a transaction committed. | Guard in-flight purchases, avoid repeat debit for an already-owned hint, and update cache after commit. |
| Rewarded hints | Completing an ad could still display the incomplete-ad warning. | Track whether the ad earned its reward. |
| Carousel | Empty filters could select index -1; nested progress changes did not automatically notify the carousel; answer state could carry across pages. | Clamp indices, forward progress changes, reset page state, and disable page/filter interaction during submission. |
| Puzzle identity | Missing IDs generated a different UUID on every access; equality and hashing used different inputs. | Use a stable fallback and hash the same identity used for equality. |
| Error recovery | Sign-in failures left a spinner; evaluation failures were hidden or labeled as wrong answers. | Add sign-in retry and visible evaluation errors; expose puzzle-loading failures. |
| Reset | The timer's played flag/cache survived reset; the confirmation overstated which progress was deleted. | Clear timer state and describe the existing reset scope accurately. |
| Sharing | Share sheets lacked an iPad popover anchor. | Anchor both puzzle and recap share sheets. |
| Logging | App Check bearer tokens were printed. | Stop printing token values. |

## Validation status

- Reviewed the modified call sites and diffs; `git diff --check` passes.
- Replaced the empty unit-test placeholder with nine regression tests covering
  production/legacy timer fields, hint retention, UTC streak behavior, and puzzle identity.
  The second pass added seven more, for 16 total; none have been executed here.
- **Remote compilation passed:** the manual GitHub Mac build on 2026-09-28 compiled
  the iPhone Release app and simulator unit-test target successfully
  ([run 36365926836](https://github.com/peytonlwhite/RebusRush/actions/runs/36365926836)).
  Tests were not executed. Firebase transaction behavior, UI layout, ads, and lifecycle
  behavior still require integration/device checks before an App Store release.
- Tests do not intentionally write database records, but the app-hosted test target
  launches the app; use a test Firebase configuration/emulator for integration runs.

## Before releasing

1. Build the app and run `PuzzleTimeTests` in Xcode with a test Firebase configuration.
2. Resume a pre-existing timer record containing word-based fields. Confirm solved cards,
   attempt counts, purchased hints, and remaining time survive closing/reopening.
3. Buy a hint, allow it to auto-hide, submit an answer, leave, and reopen in each mode.
   Verify the hint remains purchased and its reward penalty remains applied.
4. Submit repeatedly and simulate a failed/retried write. Verify one reward and one
   solved record, including a repeat from a second client using the same test account.
5. Complete timer and daily challenges around UTC midnight; verify one streak increment
   per UTC day and correct continuation/reset behavior.
6. During a timer run, test ad completion/dismissal, background/foreground, navigation
   away during evaluation/saving, and an unavailable network at Start.
7. Exercise empty/solved/unsolved filters, first-launch offline retry, reset followed by
   starting a timer, and both sharing actions on iPhone and iPad.

## Remaining follow-up areas

- Missing daily configuration still uses random fallback selection. Decide whether
  to show unavailable, use a deterministic daily fallback, or recover saved selection.
- Streak updates and medal writes are separate from answer commits. Interrupted writes
  can require reconciliation even though coins and progress now commit together.
- Coin/answer correctness is still client-controlled. Firestore rules and any deployed
  backend jobs are absent from this repo and were not audited or changed. Verify those
  before building the weekly publisher.
- Accessibility (Dynamic Type, VoiceOver, reduced motion) and notification permission
  timing need a device-based UX pass.

Weekly content automation remains deferred until this gameplay pass is validated.

## Second review pass

Additional fixes after reviewing the first pass and its interaction with existing code:

- **Failed timer reads:** clock, puzzle IDs, and results now come from one snapshot.
  Read errors and incomplete saved records show retry instead of being treated as
  a new or expired challenge. Missing saved images/puzzle records do not silently
  attach old results to different puzzles.
- **Medal restoration:** completed records store a null remaining time; their
  `timeTakenSeconds` now restores the actual finish time instead of displaying a
  three-minute finish and bronze medal for every reloaded completion.
- **Old writes:** remaining time cannot increase, and an expired/completed record
  cannot be reopened by a delayed save. The UI applies the committed clock/results.
- **Save recovery:** failed periodic/terminal saves pause the timer and show Retry
  Save. A new timer starts after its initial record commits. Backgrounding also
  attempts a checkpoint. Device/integration testing is still required, especially
  interruption during a network request and recovery after process termination.
- **UTC rollover:** open challenges continue under their original UTC date. Answer
  submissions and hint/ad callbacks retain that date through their asynchronous
  work; late completions cannot move a newer streak backward.
- **AI grading:** exact answers with case/spacing/hyphen differences succeed locally.
  Missing or malformed AI verdicts now throw a retryable error instead of consuming
  an incorrect attempt. Removed verbose prompt/answer logging.
- **Hint races:** paid and rewarded hints share one transaction. Removed unused and
  nontransactional hint writers that could undo a solve or overwrite other purchases.
- **Startup:** concurrent sign-in requests share one operation. The user document
  is created transactionally before gameplay opens, preserving existing balances.
- **Streak expiry:** stale reads no longer delete last-solved fields in Firebase.
  Expired streaks display zero; the next committed solve calculates the new streak
  from the actual stored date.
- **Ad failure:** failed home-screen ad loading now releases the shared timer pause.
  Hint ads await the tracking prompt before loading/presenting an ad.

Extend release checks with completed-record medal restoration, interrupted reads,
checkpoint retry, an old save arriving after timeout, midnight during an ad or answer
evaluation, two simultaneous sign-in requests, and a rewarded hint racing with a solve.
No live Firebase data, rules, or deployments were modified during this pass.

## Final sweep before publication

- A daily solve after UTC midnight now displays as solved using its dated progress
  record, rather than comparing the actual solve timestamp with the challenge date.
- Expired timer runs no longer receive a Solved badge. A failed home-screen progress
  read leaves the challenge accessible so its restore screen can retry.
- Answer saves reject unreadable existing progress instead of treating it as a new
  record and potentially issuing another reward.
- Timer saves require three distinct puzzles and matching saved puzzle IDs and a
  readable clock before merging progress. Each save retains its puzzle snapshot,
  and a response from an older session cannot replace a newer session's cache.

The final sweep used source/diff review; the subsequent remote Xcode build also
compiled the app and all 16 test cases. Test execution is still outstanding.
Add midnight solved-state display, expired-run badges, failed home-screen
reads, and mismatched timer puzzle IDs to the device/integration checks above.
