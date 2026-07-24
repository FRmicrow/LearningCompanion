# Research: Translation Correctness & Sync

**Branch**: `005-translation-correctness-sync` | **Date**: 2025-07-18
**Feeds into**: `plan.md`, `data-model.md`, `contracts/`

---

## Decision 1: Confirm spec 004 fixes are fully in place

**Decision**: All three spec 004 bug fixes are present in the current codebase. No re-work is required for those items.

**Rationale**: Code review of the live source confirms:

| Bug | Location | Fix status |
|-----|----------|-----------|
| Infinite `.translationTask` loop (`configuration?.invalidate()`) | `TranslationSessionHost.swift` | ✅ Fixed — `invalidate()` call absent |
| Unstable retry spinner (`.task(id: retryTrigger)`) | `VocabularyDateGroupSection.swift` | ✅ Fixed — explicit `Task {}` + `currentRetryTask` pattern in place |
| Stale `group.entries` snapshot passed to retry | `VocabularyListView.swift` | ✅ Fixed — `retryPendingTranslations()` called instead |

All 38 existing tests pass (`swift test`). The baseline is clean.

---

## Decision 2: One remaining gap — no concurrency guard on `retryPendingTranslations()`

**Decision**: `retryPendingTranslations()` has no guard against concurrent invocations. This gap must be closed to satisfy FR-009 and SC-005.

**Rationale**: The method is now called from three independent trigger sources, each of which can fire without knowledge of the others:

1. `TranslationSessionHost` — when the Apple Translation session becomes ready
2. `AppDelegate.startConnectivityMonitor()` — when `NWPathMonitor` fires on network restore
3. `VocabularyDateGroupSection` retry button — when the user taps "Réessayer"

These three triggers are independent and can overlap in time. For example: the user taps retry while simultaneously the network connectivity is restored after an offline period. Both callers fire `retryPendingTranslations()` concurrently. The current implementation has no mutual exclusion:

```swift
// Current implementation — no guard:
func retryPendingTranslations() async {
    guard let pending = try? repository.fetchPending() else { return }
    for entry in pending {
        await translate(entry: entry)   // in-flight calls for same entry from both concurrent callers
    }
}
```

Both callers fetch the same set of pending entries (both fetch before either writes "translated" back), then issue duplicate translation requests for every entry. The results are idempotent (last DB write wins), but:

- Redundant API/on-device translation calls are made (violates SC-005)
- On macOS 15+, concurrent `session.translate()` calls for the same text on the same `TranslationSession` may produce undefined behaviour per Apple's API docs

**Fix**: Add a `private var retryInProgress = false` flag to `TranslationService`, guarded by `@MainActor` (since `TranslationService` is used from the main thread in all current call sites). At entry to `retryPendingTranslations()`, check and set the flag; clear it in a `defer` block.

```swift
@MainActor private var retryInProgress = false

func retryPendingTranslations() async {
    guard !retryInProgress else { return }
    retryInProgress = true
    defer { retryInProgress = false }
    guard let pending = try? repository.fetchPending() else { return }
    for entry in pending {
        await translate(entry: entry)
    }
}
```

This is the minimal, correct fix. It does not require `actor` isolation for `TranslationService` itself (which would be a more disruptive change), because all current callers already dispatch to the main thread or use Swift concurrency in a way that makes `@MainActor` annotation safe.

**Alternatives considered**:

- **`actor TranslationService`**: Correct but requires converting the class to an actor, which would cascade to all call sites requiring `await` and potentially breaking the `@MainActor`-assumed delegate calls from `CaptureProcessorService`. Disproportionate for a single boolean guard.
- **`Task?` cancellation approach** (store the in-flight `Task`, new triggers cancel and restart): More complex; restarting a translation mid-flight wastes work. The drop-if-busy approach is simpler and correct for this use case.
- **Serial `DispatchQueue`-based lock**: Uses GCD, not Swift concurrency. Inconsistent with the rest of the codebase. Rejected.

---

## Decision 3: `TranslationService` is already `@MainActor`-compatible

**Decision**: All current call sites of `retryPendingTranslations()` already dispatch to `@MainActor` implicitly or explicitly. The `@MainActor` annotation on `retryInProgress` is valid and requires no call-site changes.

**Rationale**:

| Call site | Threading |
|-----------|-----------|
| `TranslationSessionHost` / `PersistentTranslationView` `.translationTask` callback | SwiftUI main-thread callback → safe for `@MainActor` |
| `AppDelegate.startConnectivityMonitor()` | `Task { await translationService.retryPendingTranslations() }` — inherits ambient actor (main) |
| `VocabularyDateGroupSection` button `Task {}` | Inherits ambient `@MainActor` context from SwiftUI view |
| `AppleTranslationSessionModifier` `.onAppear` | `Task { await service.retryPendingTranslations() }` — main-actor context |

All call sites are on (or hop to) the main actor. No changes to call sites required.

---

## Decision 4: No schema changes required

**Decision**: No new DB columns, no new migration version.

**Rationale**: `translationStatus` (pending / translated) and `frenchTranslation` are sufficient. The concurrency guard lives entirely in memory within `TranslationService`. GRDB `ValueObservation` continues to drive all live UI updates.

---

## Decision 5: Test strategy — one new unit test

**Decision**: Add one new `@Test` to `TranslationServiceTests.swift` verifying that a concurrent second call to `retryPendingTranslations()` is a no-op while the first is in flight.

**Rationale**: The concurrency guard is pure logic in `TranslationService` and is fully testable with an in-memory DB and a slow mock. This is the only new code change, so exactly one new test is needed.

The approach: use `Task.detached` to launch two concurrent calls; confirm via DB state that entries are translated exactly once and that the method completed without double-translating.

**What existing tests already cover** (no change needed):
- `translate(entry:)` never throws — covered
- `retryGroup` throws when all fail — covered
- `retryPendingTranslations()` is a no-op when nothing is pending — covered
- Entry stays pending on network failure — covered

---

## Decision 6: No new user-facing strings

**Decision**: The concurrency guard is invisible to the user; no new `L10n` keys required.

**Rationale**: The guard silently drops duplicate retry calls. No error state, no UI feedback. The existing "retry service error" string already covers the case where all entries fail; nothing new is needed.

---

## Summary Table

| Concern | Status | Action |
|---------|--------|--------|
| Infinite session callback loop | ✅ Fixed in spec 004 | No change |
| Unstable retry spinner | ✅ Fixed in spec 004 | No change |
| Stale entry snapshot in retry | ✅ Fixed in spec 004 | No change |
| Concurrent `retryPendingTranslations()` calls (FR-009, SC-005) | ⚠️ Open gap | Add `@MainActor retryInProgress` flag to `TranslationService` |
| Schema | Unchanged | No change |
| Tests | Baseline green (38 tests) | Add 1 new test for concurrency guard |
