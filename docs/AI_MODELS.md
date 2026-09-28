# AI model configuration

Reviewed September 27, 2026.

| Feature | Provider | Model | Configuration |
| --- | --- | --- | --- |
| iPhone answer checking | Firebase AI Logic, Gemini Developer API (`.googleAI()`) | `gemini-3.5-flash` | `RiddleEvaluator.modelName` |
| Weekly puzzle generation and image review | Vertex AI, global endpoint | `gemini-3.5-flash` | `PUZZLE_MODEL` in the deployed function, default in `functions/src/index.js` |

The app previously used `gemini-2.5-flash`. Google currently lists 3.5 Flash as a supported stable model with availability through at least May 19, 2027. Newer short-term Flash releases exist, but this migration keeps both features on the supported longer-lived version.

Sources:

- [Firebase supported models](https://firebase.google.com/docs/ai-logic/models)
- [Vertex model lifecycle](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions)
- [Firebase shutdown guidance](https://firebase.google.com/docs/ai-logic/faq-and-troubleshooting)
- [Gemini Developer API deprecations](https://ai.google.dev/gemini-api/docs/deprecations)

The 2.5 retirement guidance differs by provider and currently conflicts across Google's pages: Firebase's FAQ says October 16, 2026 for Google AI and October 20 for Vertex, while the Developer API deprecations page says no shutdown date is announced for existing 2.5 Flash users. Do not apply the Vertex deadline to the iPhone app as a confirmed fact. The upgrade removes this dependency without changing API provider or app security.

Validation: six live grading cases using the app's unchanged prompt passed on 3.5 Flash through Vertex (answer variants, a small spelling error, and clearly wrong answers). Flash-Lite rejected the spelling-error case, so it was not selected. These are model behavior checks, not an end-to-end iPhone test. A direct Firebase Google AI probe was rejected by App Check; no security setting was relaxed. Verify answer checking on a signed iPhone build before App Store release.

Changing this Swift constant requires a new TestFlight/App Store build. Already-installed builds keep their bundled model name. The scheduled Firebase function already uses 3.5 Flash and does not need redeployment for this change.
