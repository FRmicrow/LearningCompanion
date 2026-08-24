<!-- SYNC IMPACT REPORT
Version change: 1.0.1 → 1.0.2
Modified principles: none
Added sections: none
Removed sections: none
Templates checked:
  ✅ .specify/templates/plan-template.md — no change required; Constitution Check gate text is generic
  ✅ .specify/templates/spec-template.md — no change required
  ✅ .specify/templates/tasks-template.md — no change required; Swift Testing not referenced (generic template)
  ✅ README.md — consistent with constitution; libretranslate.com appears only as a hyperlink label, runtime URL is localhost:5001 in AppDelegate
Follow-up TODOs: none
-->

# ClipboardVocab Constitution

## Core Principles

### I. Local-First, Privacy-Safe

All vocabulary data MUST be stored exclusively on the user's device. The app MUST NOT
transmit clipboard content to any remote service beyond the local translation endpoint.

The translation backend is **LibreTranslate running locally in Docker** on
`http://localhost:5001/translate` — no API key required, no external network call is
made for translation. This URL is hardwired in `AppDelegate.applicationDidFinishLaunching`
and overrides the `TranslationService` class default (`libretranslate.com`). If Docker
is not running, translations fail gracefully: entries are stored as `.pending` and
retried automatically when the service becomes reachable.

On macOS 15+, the Apple on-device `Translation` framework is used instead (injected
via `TranslationSessionHost`), which is also fully local and requires no network at all.

No cloud sync, no analytics, no telemetry, no remote logging. Clipboard content that
fails to translate MUST be stored locally as `.pending` and retried locally — it MUST
NOT be discarded and MUST NOT be retried via a different endpoint without user consent.

**Rationale**: The app reads every clipboard copy the user makes. Keeping translation
local (Docker or on-device) ensures no clipboard content ever leaves the machine,
satisfying the strongest reasonable privacy guarantee.

### II. Silent, Non-Interruptive Operation

The app MUST operate completely silently during normal use. This means:

- No system notifications, no sounds, no Dock icon (`LSUIElement = YES` in `Info.plist`).
- Clipboard captures are processed entirely in the background — the user MUST NOT need
  to interact with the app for capture, filtering, or translation to occur.
- All discard events (non-English, too long, low confidence, URL, numeric) MUST be
  silently dropped with no user-visible indication.
- The only user-visible surfaces are the `NSStatusItem` menu bar icon and the
  `NSPopover` vocabulary panel, opened explicitly on demand.

**Rationale**: Silent operation is the core value proposition. An app that interrupts
the user's clipboard workflow defeats its own purpose.

### III. Test-Discipline (NON-NEGOTIABLE)

All new logic MUST be covered by tests using **Swift Testing** (`import Testing`,
`@Suite`, `@Test`, `#expect`). XCTest MUST NOT be introduced; the two frameworks are
incompatible and MUST NOT be mixed.

- Unit tests go in `Tests/Unit/`, integration tests in `Tests/Integration/`.
- Async delegate tests MUST use the `nonisolated` + `Task { await self.appendX(...) }`
  pattern; do not re-dispatch callbacks that are already dispatched to the main thread.
- Integration test `CaptureToStorageTests.testCaptureLatencyWithinThreeSeconds`
  enforces SC-001 (≤ 3000 ms end-to-end). This test MUST NOT be removed or relaxed.
- In-memory DB for tests: `Database(path: ":memory:")` — never use a tmp file path.

**Rationale**: Silent background processing makes manual regression testing slow and
unreliable. Automated tests are the only practical regression gate.

### IV. Contract-Driven Service Design

Each service MUST have a corresponding contract document in the relevant
`specs/###-feature/contracts/` directory. The contract is the authoritative definition
of method signatures, threading guarantees, and error contracts. Code MUST NOT deviate
from a ratified contract without first amending the contract document.

Key non-negotiable contracts currently in force:

- `TranslationService.translate(entry:)` MUST be `async`, MUST NOT throw.
- `TranslationService.retryGroup(entries:)` MUST throw only when `successCount == 0`.
- `CaptureProcessorService` delegate callbacks MUST be dispatched to the main thread
  via `@MainActor` private helpers; callers MUST NOT re-dispatch.
- GRDB `ValueObservation` MUST be the exclusive mechanism for live UI updates
  (no `NotificationCenter`, no manual refresh).

**Rationale**: ClipboardVocab's pipeline chains multiple async services. Undocumented
threading or error contract changes produce subtle race conditions that are
disproportionately hard to reproduce and debug.

### V. Simplicity — No Unjustified Complexity

New Swift Package Manager dependencies MUST NOT be added without documenting the
justification in the relevant `plan.md` Complexity Tracking table. Architectural
patterns (repositories, coordinators, additional abstraction layers) MUST NOT be
introduced unless a Constitution Check gate violation in `plan.md` explicitly justifies
them.

Schema migrations are forward-only. Additive changes (`ALTER TABLE … ADD COLUMN`) are
preferred; destructive schema changes require a new DB file and MUST be flagged in the
Complexity Tracking table.

**Rationale**: The app is a single-user, single-machine menu bar tool. Complexity
added beyond the current service pipeline has a real maintenance cost with no
proportional user benefit.

## Performance & Resource Constraints

These constraints are non-negotiable success criteria derived from SC-001 and SC-003
and MUST be respected by every feature:

| Constraint | Limit | Verification |
|---|---|---|
| Capture-to-DB-insert latency | ≤ 3,000 ms | `CaptureToStorageTests` SC-001 |
| Background CPU at idle | < 1% | Manual — Activity Monitor |
| Background RAM | < 50 MB | Manual — Activity Monitor |
| Language detection accuracy (clear EN/FR) | > 95% | `LanguageDetectionTests` corpus |

Any feature that risks breaching a constraint MUST include a timing/resource validation
step in its `quickstart.md` manual scenarios.

## Development Workflow

- All features MUST follow the speckit pipeline:
  `/speckit.specify` → `/speckit.plan` → `/speckit.tasks` → implementation.
- Each feature spec directory (`specs/###-feature/`) MUST contain `spec.md`,
  `plan.md`, and at least one `contracts/` file before implementation begins.
- The `plan.md` Constitution Check gate MUST be completed before Phase 0 research and
  re-verified after Phase 1 design. A failing gate blocks all implementation work.
- Localized strings MUST use `L10n.string(_:)` in `ClipboardVocab/Models/L10n.swift`;
  bare `NSLocalizedString` MUST NOT be used (it resolves `Bundle.main` which is wrong
  in SPM executables).

## Governance

This constitution supersedes all informal conventions and historical plan comments.
Where a `plan.md` Constitution Check previously noted "no principles in force", the
principles above apply retroactively for any future amendments to those features.

**Amendment procedure**: Any change to a Core Principle or constraint requires:
1. A PR or commit updating this file with a version bump justified in the commit message.
2. The Sync Impact Report (HTML comment at top of file) updated to list affected templates.
3. Existing `plan.md` files for active specs reviewed and their Constitution Check
   sections updated if the amendment adds new gates.

**Versioning policy**:
- MAJOR: Backward-incompatible removal or redefinition of a principle.
- MINOR: New principle or section added; material expansion of existing guidance.
- PATCH: Clarifications, wording fixes, non-semantic refinements.

**Compliance review**: Every `plan.md` Constitution Check gate MUST reference the
current version of this document. Outdated gates MUST be updated before the feature
moves to the implementation phase.

**Version**: 1.0.2 | **Ratified**: 2025-07-18 | **Last Amended**: 2025-08-24
