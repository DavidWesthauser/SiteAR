# AI use and handover preparation

OpenAI Codex was used extensively for Swift/SwiftUI/ARKit implementation, Supabase migrations, tests, debugging and documentation. Focused subagents reviewed UI and tracking changes and implemented a small pure rendering-budget helper. Generated code was checked with compilation, deterministic tests, UI automation, screenshots and code review; physical AR and live backend acceptance remain separate.

Concrete examples of generated code that needed correction:

- Commit `88d4de7`: the first animated miniature could be invisible before its animation clock advanced. Screenshot review exposed this despite passing layout assertions. Existing geometry now renders immediately; `testMiniatureRendersWithoutAnAnimationClock` checks actual rendered pixels.
- Commit `ece3928`: the frozen-view workflow allowed concurrent snapshot requests. Focused review identified a stale callback that could clear a valid drawing plane. `ViewCaptureRequest` now rejects duplicate/stale requests and cancels them on reset, resume, stop and tracking loss; a deterministic test covers the ordering.
- Commit `ece3928`: a long-scan review found per-edge render entities, repeated searches and continuous unbounded miniature work. Display geometry is now sampled/bounded and batched, with pressure-driven detail reduction. Stress tests do not prove that the user's device crash is fixed.

These are factual development examples, **not claims that either student personally performed the review or understands the code**. Both students' individual reflections are pending and must be written from their actual experience. Do not invent contribution histories, reviews or earlier commits.

For each student, record before submission:

- Actual name, owned feature/files and genuine commits.
- Which AI tool was used and for what.
- One concrete suggestion/code fragment they personally checked, corrected or rejected; include the commit when available.
- Their reasoning, test evidence and what they learned.

Handover topics to understand and explain:

1. Room coordinates, session coordinates and why transforms must be multiplied in the right order.
2. Why loading an ARWorldMap alone does not prove alignment, and why drawings hide on tracking loss.
3. Marker alignment versus map alignment and explicit fallback confirmation.
4. Which data lives in private Storage versus Postgres, and how RLS blocks outsiders.
5. Local Debug mode versus required cloud persistence; what each automated test actually proves.
6. Why bounded visualization can reduce workload without improving ARKit's recognition algorithm or changing annotation positions.
7. Failure/lifecycle handling, remaining limitations and the physical acceptance procedure.
