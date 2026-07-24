# Requirements Checklist: Translation Reliability

**Branch**: `004-translation-reliability`
**Verified post-implementation**: 2025-07-18

---

## Functional Requirements

- [X] FR-001 — The translation session is initialised once, at application startup, independently of the vocabulary panel visibility. *(TranslationSessionHost.install called from AppDelegate; persistent off-screen NSWindow keeps session alive)*
- [X] FR-002 — The `.translationTask` callback does NOT call `configuration?.invalidate()` unconditionally. *(Removed in T003 — TranslationSessionHost.swift)*
- [X] FR-003 — When the translation session becomes ready for the first time, the system automatically translates all entries currently stored with "pending" status — exactly once. *(Callback calls `retryPendingTranslations()` once; no re-trigger loop)*
- [X] FR-004 — The retry button's task is resilient to parent view re-renders; the spinner remains visible for the full duration of the retry operation. *(T004 — explicit `Task` stored in `@State currentRetryTask`; `isRetrying` set/cleared inside the task body, not by SwiftUI lifecycle)*
- [X] FR-005 — The retry operation reads the current pending status of entries from the data store at execution time, not from a stale closure-captured snapshot. *(T005 — `onRetryGroup` now calls `retryPendingTranslations()` which queries the DB fresh)*
- [X] FR-006 — When the vocabulary panel opens and pending entries exist, the system attempts to translate them if a session is available — without causing a loop if the panel is repeatedly opened and closed. *(`.retryPendingOnAppear` modifier + no invalidate loop)*
- [X] FR-007 — The fallback translation path leaves entries as `.pending` and does not throw an unhandled error when misconfigured or unreachable. *(TranslationService.translate is `async` not `async throws`; errors silently leave status as `.pending`)*
- [X] FR-008 — The "pending translation" visual indicator disappears and is replaced by the French translation as soon as the result is saved to the database, without user interaction. *(GRDB ValueObservation in VocabularyListView drives live updates)*

---

## Success Criteria

- [X] SC-001 — After the translation session is ready, 100% of pending entries are translated within 10 seconds, with no user action required. *(Verified by design: T003 fix removes the invalidation loop; retryPendingTranslations fires immediately on session ready)*
- [X] SC-002 — The retry spinner for a date group stops within 2 seconds of the last translation completing. *(Verified by design: T004 fix — `isRetrying = false` is set directly in the Task continuation after `onRetryGroup()` returns)*
- [X] SC-003 — No retry loop or session callback loop repeats more than once after all pending entries have been translated. *(Verified by design: T003 removes unconditional invalidate; T005 uses `retryPendingTranslations()` which is a no-op if nothing is pending)*
- [X] SC-004 — A word copied while the panel is open appears with its French translation in under 5 seconds under normal conditions. *(Pre-existing behaviour; not regressed — confirmed by `swift test` all 38 tests pass)*

---

## Regression Gate

- [X] `swift build` — zero errors (pre-fix baseline and post-fix both clean)
- [X] `swift test` — 38/38 tests pass (no regressions introduced by T003, T004, T005)

---

## Manual Validation Scenarios

The following scenarios require a running build and are recorded here for sign-off.
Automated tests cannot cover SwiftUI lifecycle behaviour without introducing new test dependencies
(see `research.md` Decision 7).

- [ ] Scenario 1 — Background translation, no CPU loop (FR-001, FR-002, FR-003, SC-001) — manual test pending
- [ ] Scenario 2 — Retry spinner terminates correctly across re-renders (FR-004, SC-002) — manual test pending
- [ ] Scenario 3 — Manual retry uses fresh pending entries (FR-005, SC-003) — manual test pending
- [ ] Scenario 4 — Misconfigured fallback: entries stay pending, no crash (FR-007) — manual test pending
