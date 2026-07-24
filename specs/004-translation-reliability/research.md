# Research: Translation Reliability

**Branch**: `004-translation-reliability` | **Date**: 2025-07-18 (updated)
**Feeds into**: `plan.md`, `data-model.md`, `contracts/`

---

## Decision 1: Root cause of permanent "pending" entries — infinite `.translationTask` loop

**Decision**: The primary root cause is a self-triggering loop in `TranslationSessionHost.swift`, not a session scoping issue.

**Rationale**: `TranslationSessionHost` already exists as a persistent, always-alive hidden `NSWindow` (created in `AppDelegate.applicationDidFinishLaunching`). It hosts `PersistentTranslationView`, which attaches a `.translationTask(configuration)` modifier. On macOS 15+, when the Apple on-device EN→FR model is ready, the callback fires and correctly sets `service.appleSession = session` and calls `await service.retryPendingTranslations()`.

However, the callback immediately calls `configuration?.invalidate()`. Per Apple's `TranslationSession.Configuration` API, calling `invalidate()` on the active configuration schedules the `.translationTask` callback to fire again. This creates:

```
.translationTask callback fires
  → service.appleSession = session
  → retryPendingTranslations() (OK on first pass)
  → configuration?.invalidate()        ← re-schedules the callback
.translationTask callback fires again
  → service.appleSession = session     ← replaces in-flight session reference
  → retryPendingTranslations()         ← redundant (nothing pending)
  → configuration?.invalidate()        ← re-schedules again
...indefinitely
```

Re-assigning `service.appleSession` while `translate(entry:)` is in-flight can cancel the in-progress `session.translate(text)` call, causing entries to remain `.pending`.

**Fix**: Delete the `configuration?.invalidate()` call. The `.translationTask` callback already fires naturally when a session becomes available or after a language model download. Unconditional invalidation is counter-productive.

**Alternatives considered**:
- Call `invalidate()` only when `appleSession` was previously nil: fixes the loop but is more complex; removing the line entirely is simpler and correct.
- Use `LanguageAvailability.status(for:)` to guard invalidation: valid for future download-detection, but out of scope for this bug fix.

---

## Decision 2: Root cause of infinite retry spinner — `.task(id:)` on a value-type view struct

**Decision**: The spinner state corruption is caused by SwiftUI re-creating `VocabularyDateGroupSection` (a value-type `struct`) during `ValueObservation`-driven re-renders, resetting `@State isRetrying` mid-flight.

**Rationale**: `VocabularyDateGroupSection` is a SwiftUI `struct`. Every time `VocabularyListView` re-renders with new `@State entries` (which happens on every DB write, since `ValueObservation` fires on each successful translation), SwiftUI may destroy and recreate view instances in the `List`. When the view identity changes, `@State` is reset. `isRetrying` goes back to `false`, and the in-flight `.task(id: retryTrigger)` has no view to write its `defer { isRetrying = false }` into.

The result is non-deterministic: the spinner may disappear early (view recreated → `isRetrying = false` while task is running), stay permanently (task cancelled on view teardown, `defer` not reached), or toggle rapidly.

**Fix**: Replace the `.task(id: retryTrigger)` pattern with an explicit `Task {}` stored in `@State var currentRetryTask: Task<Void, Never>?`. The task is launched from the button's action closure, where `isRetrying = true` is set synchronously before the task launches. `isRetrying = false` is set inside the `Task` body (not via `defer` on the `.task` modifier), ensuring the write goes through `@MainActor` on the live view even if the view struct value is recreated.

```swift
// BEFORE (broken):
Button(L10n.string("retry_group_label")) {
    retryTrigger += 1
}
.task(id: retryTrigger) {
    guard retryTrigger > 0 else { return }
    isRetrying = true
    defer { isRetrying = false }
    do { _ = try await onRetryGroup() } catch { retryError = ... }
}

// AFTER:
Button(L10n.string("retry_group_label")) {
    guard !isRetrying else { return }
    isRetrying = true
    retryError = nil
    currentRetryTask = Task {
        defer {
            Task { @MainActor in isRetrying = false }
        }
        do { _ = try await onRetryGroup() } catch {
            Task { @MainActor in retryError = L10n.string("retry_service_error") }
        }
    }
}
```

**Alternatives considered**:
- Lift `isRetrying` to `VocabularyListView` as a per-group dictionary `[String: Bool]`: works but is more invasive; the explicit `Task` is minimal.
- Use `@StateObject` with an `ObservableObject`: adds a class-type coordinator; valid but heavier than needed for a single boolean.

---

## Decision 3: Stale entry snapshot passed to `retryGroup`

**Decision**: Change the `onRetryGroup` closure in `VocabularyListView` to call `translationService.retryPendingTranslations()` (which fetches live pending entries from the DB at call time) rather than passing the render-time `group.entries` snapshot to `retryGroup(entries:)`.

**Rationale**: `group.entries` is a value captured at the time the `VocabularyDateGroupSection` view is constructed. By the time the user taps the button and the task runs, the background retry loop (from Decision 1's fix or from `NWPathMonitor`) may have already translated some of those entries. `retryGroup` internally re-filters for `.pending` status, so it is idempotent — but it wastes API calls on entries whose status in the DB is already `translated`.

Using `retryPendingTranslations()` (which calls `repository.fetchPending()` fresh) ensures only genuinely pending entries are retranslated, regardless of view render lag.

**Note**: This changes the scope from "retry only entries in this date group" to "retry all pending entries globally". If per-group retry scope is a future UX requirement, the correct approach is to add `repository.fetchPending(capturedBetween:)` scoped by the group's date range, called at execution time — not from a closure-captured snapshot. This is deferred as a future enhancement.

**Alternatives considered**:
- Pass a date range to `retryGroup` and scope it: valid improvement, but out of scope for this reliability fix.
- Keep `group.entries` but re-fetch from DB inside `retryGroup`: requires adding a DB-fetch path to `TranslationService`, which should not own repository query logic. Current design is correct — caller passes entries, service translates them.

---

## Decision 4: Session lifecycle location (confirming existing architecture is correct)

**Decision**: `TranslationSessionHost` (persistent hidden `NSWindow`) is the correct place for the Apple Translation session. No changes to its lifecycle structure — only the `invalidate()` line is removed.

**Rationale**: The `TranslationSessionHost` was introduced precisely to decouple the session from the popover's visibility. The architecture is correct. The only bug is the unconditional `invalidate()` call inside it.

**Confirmed**: `AppDelegate.applicationDidFinishLaunching` calls `TranslationSessionHost.install(translationService:)` which creates the hidden window. The `PersistentTranslationView` holds the configuration and fires the `.translationTask` callback as soon as the model is available. This is the right approach.

---

## Decision 5: LibreTranslate fallback default (confirmed correct in current code)

**Decision**: `TranslationService.libreTranslateURL` already defaults to `https://libretranslate.com/translate`. No change needed here — the property default in `TranslationService.swift` is already the public instance.

**Rationale**: Earlier research identified a discrepancy where `AppDelegate` was overriding this with `localhost:5000`. Reviewing the current `AppDelegate.swift`, there is no override — the `libreTranslateURL` property uses its declared default. If a prior fix was already applied, no further change is required. The property default in `TranslationService.swift:31` reads `https://libretranslate.com/translate`, which is correct.

---

## Decision 6: No schema changes required

**Decision**: No new DB columns, no new migration version.

**Rationale**: Unchanged from prior research. `translationStatus` and `frenchTranslation` are sufficient. GRDB `ValueObservation` fires on every write, driving live UI updates.

---

## Decision 7: Test strategy

**Decision**: Existing `TranslationServiceTests.swift` coverage is sufficient. The three bugs are in UI/lifecycle code, not in `TranslationService` logic. No new tests are strictly required; the existing tests already verify the never-throws contract and retry-on-failure behaviour.

**Rationale**: Bug 1 (infinite loop) and Bug 2 (spinner state) are SwiftUI lifecycle issues that cannot be meaningfully unit tested without a live SwiftUI environment. The `quickstart.md` manual test scenarios cover these. Bug 3 (stale snapshot) is idempotency-level — existing `retryGroup` tests already prove the filter works.

If a regression test for Bug 2 is desired, it would require a SwiftUI `ViewInspector` dependency or a UI test target, both of which are out of scope per the no-new-dependencies constraint.

---

## Summary Table

| Concern | Root cause location | Resolution | FR / SC |
|---------|------------|-----------|---------|
| Entries stay permanently pending / session loop | `TranslationSessionHost.swift:83` — `configuration?.invalidate()` | Delete that line | FR-001, FR-002, FR-003, SC-001 |
| Retry spinner never stops | `VocabularyDateGroupSection.swift:85` — `.task(id:)` on value-type view | Replace with explicit `Task {}` in button action | FR-004, SC-002 |
| Redundant retry API calls / stale snapshot | `VocabularyListView.swift:82` — closure captures `group.entries` | Use `retryPendingTranslations()` which fetches fresh pending entries | FR-005, SC-003 |
| UI updates without manual refresh | Already resolved by GRDB `ValueObservation` — no change needed | N/A | FR-008 |
| Schema changes | None required | N/A | N/A |
