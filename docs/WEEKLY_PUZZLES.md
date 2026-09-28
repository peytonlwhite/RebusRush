# Weekly puzzle generation

## Implementation and deployment status

The implementation is in `functions/`. The function is deployed and ACTIVE, and its Cloud Scheduler job is ENABLED for Mondays at 09:00 America/Chicago. All 12 pipeline tests pass locally on Node 22 and in GitHub Actions. The first live generation run is undergoing verification; no successful initial publication has been recorded in this document yet.

The first version produces text/shape rebuses, not illustrated scenes. Gemini designs the puzzles and independently checks the rendered images. A deterministic SVG-to-PNG renderer controls spelling, layout, gradients and branding. No third-party puzzle site is scraped. Familiar English phrases and rebus mechanics are allowed; hints, explanations and layouts are authored for this app.

## Schedule and output

- Monday at 09:00 in `America/Chicago`, including daylight-saving changes.
- Firebase scheduled function `generateWeeklyPuzzles`, `us-central1`, separate codebase `weekly-puzzles`.
- Target: exactly 20 puzzles, 1080 × 1080 PNGs with white bold Noto Sans, a diagonal blue-purple gradient and the existing RebusRush logo at 18% opacity in the upper-right.
- The image/logo template is `functions/src/render.js`; the logo is a copy of the app's existing asset.
- Gemini model is configurable using `PUZZLE_MODEL`, default `gemini-3.5-flash`. Google lists this stable model's retirement as May 19, 2027 or later (checked September 27, 2026). Review model availability before that date.
- Required app fields: `answer`, `hints` (three), `explanation`, `photoUrl`, `createdAt`. The timestamp is essential because the existing app queries with `order(by: "createdAt")`.
- New puzzles join the regular library. Existing `dailyChallenges` and `timerRiddlesDaily` selections are not rewritten by this job.

## Generation and failure handling

1. Acquire a 35-minute lease on `riddleGenerationRuns/{Monday-date}`. A completed week is a no-op.
2. Read existing riddle answers and previously attempted candidates. Generate in batches of ten, up to 60 candidate slots per week. No more than five accepted puzzles may share one mechanic.
3. Validate the JSON, all three hints, allowed characters, actual glyph bounds and text overlap. Reject exact normalized answer duplicates and exact layout duplicates. The generation prompt excludes trivial paraphrases, and the editorial model separately checks the answer against the existing library; semantic duplicate detection is still best-effort.
4. Independently solve each PNG without supplying its answer. Require the same normalized answer, at least 0.85 reported confidence, and no ambiguity. A second editorial call checks the intended answer, clues, hints, explanation and family suitability. AI checks reduce errors; they are not proof of human solvability.
5. Save accepted/rejected candidates in the run's `candidates` subcollection. These are never placed in the live `riddles` collection as drafts.
6. Upload all 20 PNGs under `riddles/generated/{Monday-date}/`. Writes use Storage generation preconditions, immutable cache headers and download-token URLs matching the app's existing image format. Existing objects are reused only if their content hash matches.
7. Atomically create all 20 Firestore records and mark the weekly run complete. A fresh transaction checks the library again before publishing. Existing records are never overwritten.

Partial Storage uploads remain available for a retry but are not playable until the Firestore transaction succeeds. If fewer than 20 candidates pass, nothing is published; candidates and the reason remain in the run. A Scheduler retry is allowed once. Retry accounting persists: at most 140 model requests and 60 candidate slots per week, including failures. A model call has a 90-second timeout; the function has a 30-minute timeout and one instance. These are usage limits, not a dollar-denominated billing cap. Cloud Functions, Storage, Firestore, Scheduler and Gemini usage can incur charges on the existing Blaze plan.

To pause publication, set `adminSettings/weeklyPuzzles.enabled` to `false`. The handler checks this at the start of each invocation and again inside the final publication transaction. An in-progress run may still consume generation calls and upload images, but it will not publish while paused. To inspect problems, check Cloud Logging and `riddleGenerationRuns/{week}.lastError`. Error notifications are not separately configured by this code.

## Local development

Use Node 22 (the deployed runtime), then:

```sh
npm ci --prefix functions
npm test --prefix functions
npm run preview --prefix functions
```

`functions/output/index.html` is a searchable preview gallery with six authored style examples. These are visual samples, not a generated or published weekly batch. The gallery and PNGs are ignored by Git. Tests use in-memory Firestore/Storage adapters, not production data, and cover weekly dates, validation, rendering, QA gates, exact batch size, duplicate prevention, concurrent execution, failed uploads and retries.

Font licensing is supplied by `@fontsource/noto-sans` under SIL OFL 1.1. Its outlines are embedded in rendered images. UUID versions below 11.1.1 are overridden to the compatible CommonJS security fix `uuid@11.1.1`; the affected gaxios dependency only calls `v4()`. The override is compatible with npm 10 used by the Node 22 cloud builder.

## Deploy and run

```sh
npx firebase-tools@15.31.0 login
# First create functions/.env.puzzle-time-72ad9 containing: PUZZLE_MODEL=gemini-3.5-flash
npx firebase-tools@15.31.0 deploy --only functions:weekly-puzzles --project puzzle-time-72ad9
```

Deployment uses the official Firebase CLI's account authorization. Runtime access uses Google's application-default service identity; no API keys or service-account private keys are committed. The project needs Cloud Functions/Run, Cloud Build, Artifact Registry, Eventarc, Cloud Scheduler and Vertex AI enabled. The runtime identity needs access to Firestore, the existing Storage bucket and Vertex AI inference. Use existing permissions where sufficient; do not weaken database or Storage security rules to make deployment work.

### Firestore rules prerequisite and existing security issue

The deployed rules originally allowed anyone to read/write all Firestore data until November 29, 2026. The scoped `firestore.rules` change protects `riddleGenerationRuns/**` and `adminSettings/weeklyPuzzles/**` from ALL client reads/writes, including signed-in clients; Admin/IAM access still works. Thirty-six cases passed Google's Rules test API before deployment. Existing app collections retain their earlier access behavior to avoid an untested gameplay migration. This is **not a full database security hardening**: existing public access must be replaced with tested per-user/content rules, and the original expiry date is unchanged. Treat that as an urgent separate follow-up.

Deploy the scoped automation protection using `firebase deploy --only firestore:rules --project puzzle-time-72ad9` before triggering this function in a new environment. Do not run an unprotected automation ledger under a public-write catch-all rule.

After deployment, run the function's Cloud Scheduler job once from Google Cloud Console. Verify a `published` run with exactly 20 IDs, check the images, and confirm the next Monday schedule. Re-running the same calendar week must not add another batch. The first manually triggered run counts toward that week's 20.

Do not use `firebase deploy` without the scoped `--only` flag: the repo does not manage all existing Firebase services or functions.
