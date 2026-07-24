# ClipboardVocab

A macOS menu bar app for French speakers learning English. Whenever you copy an English word or short phrase, ClipboardVocab silently captures it, translates it to French, and adds it to a local vocabulary list — no interaction required.

---

## How it works

1. The app runs invisibly in the background (no Dock icon).
2. Every 500 ms it checks the macOS clipboard for new plain-text content.
3. If the text is English and ≤ 50 characters, it is saved to a local SQLite database and translated to French via a **self-hosted [LibreTranslate](https://libretranslate.com/)** container running on `localhost:5001`.
4. Click the menu bar icon at any time to review your vocabulary list.
5. Press **⌘ Shift C** to instantly pause or resume capture.

```
Copy "threshold" from any app
        │
        ▼  (≤ 500 ms)
ClipboardVocab detects English, confidence ≥ 0.6
        │
        ▼
Saves entry  →  frenchTranslation = "seuil"  ✓
        │
        ▼
Click menu bar icon → see your full vocabulary list
```

---

## Features

| Feature | Details |
|---------|---------|
| **Silent capture** | No notification, no sound, no interruption |
| **Language gate** | French, non-text, URLs, numbers, paths — all silently ignored |
| **Length gate** | Only words and short phrases ≤ 50 characters |
| **Deduplication** | Same word captured twice → "seen N times" counter, no duplicate |
| **Translation pending** | Captured offline? Entry saved immediately, translated when back online |
| **Manual retry** | Tap the retry badge on any pending entry |
| **Pause / Resume** | ⌘ Shift C or right-click menu item — icon changes to reflect state |
| **Delete entries** | Swipe or tap the trash button; re-capturing creates a fresh entry |
| **Persistent storage** | SQLite file survives restarts and reboots |

---

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 Ventura or later |
| Swift | 5.9+ |
| Xcode | 15.0+ (for Xcode builds) |
| Swift Package Manager | Bundled with Swift |

> **Translation note**: the app calls a **self-hosted LibreTranslate** instance on `http://localhost:5001`. See [Installation](#installation) for setup instructions.

---

## Installation

This section covers how to install ClipboardVocab from the pre-built DMG — no Xcode or Swift toolchain required.

### Step 1 — Install Docker Desktop

LibreTranslate (the translation engine) runs as a local Docker container. Download and install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/) then launch it and wait until the whale icon appears in the menu bar.

### Step 2 — Start the LibreTranslate container

Open **Terminal** and run:

```bash
docker run -d \
  --name libretranslate \
  --restart unless-stopped \
  -p 5001:5000 \
  libretranslate/libretranslate:latest \
  --load-only en,fr
```

The first run downloads the language models (~500 MB). Wait until the container status shows **healthy**:

```bash
docker ps --filter name=libretranslate
```

Verify the API is up:

```bash
curl http://localhost:5001/languages
# Expected: JSON array containing "en" and "fr"
```

> **To stop** (translations will queue as pending until it restarts): `docker stop libretranslate`
> **To restart after reboot**: Docker Desktop auto-restarts the container because `--restart unless-stopped` is set.

### Step 3 — Install ClipboardVocab

1. Open `ClipboardVocab.dmg`.
2. Drag **ClipboardVocab** into the **Applications** folder.
3. Eject the disk image.

#### Gatekeeper — first launch

Because the app is **not notarised by Apple**, macOS will block the first launch. To allow it:

**Option A — Finder:**
1. Right-click `ClipboardVocab.app` in Applications.
2. Click **Open**.
3. Click **Open** again in the dialog.

**Option B — Terminal:**
```bash
xattr -dr com.apple.quarantine /Applications/ClipboardVocab.app
```
Then double-click the app normally.

### Step 4 — Grant Accessibility permission

The global **⌘ Shift C** shortcut requires Accessibility access:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click **+** and add **ClipboardVocab**.
3. Toggle it **on**.

If the shortcut still does not work after granting access, quit and relaunch the app.

### Step 5 — Launch and use

- ClipboardVocab appears as an icon in the **menu bar** (no Dock icon).
- Copy any English word or short phrase from any app — it is captured automatically.
- Click the menu bar icon to see your vocabulary list.
- Press **⌘ Shift C** to pause or resume capture at any time.

---

## Project structure

```
ClipboardVocab/
├── App/
│   ├── main.swift                   # NSApplication entry point
│   ├── AppDelegate.swift            # Lifecycle, service wiring, global shortcut
│   ├── Info.plist                   # LSUIElement = YES (no Dock icon)
│   └── ClipboardVocab.entitlements  # Sandbox + network.client
├── Models/
│   ├── CaptureState.swift           # enum .active / .paused
│   └── VocabularyEntry.swift        # Codable + GRDB record
├── Persistence/
│   ├── Database.swift               # GRDB DatabaseQueue, migrations
│   └── VocabularyEntryRepository.swift  # upsert / delete / fetchAll / fetchPending
├── Services/
│   ├── ClipboardMonitorService.swift    # 500 ms NSPasteboard polling
│   ├── CaptureProcessorService.swift   # Full filter pipeline
│   ├── LanguageDetectionService.swift  # NLLanguageRecognizer wrapper
│   ├── TranslationService.swift        # LibreTranslate HTTP + retry
│   └── GlobalShortcutManager.swift     # Carbon RegisterEventHotKey (⌘ Shift C)
└── UI/
    ├── StatusItemController.swift   # NSStatusItem + NSPopover lifecycle
    ├── VocabularyListView.swift     # SwiftUI List, GRDB ValueObservation
    ├── VocabularyEntryRow.swift     # Entry row: EN, FR, seen count, delete, retry
    └── EmptyStateView.swift         # French empty-state placeholder

Tests/
├── Unit/
│   ├── VocabularyEntryRepositoryTests.swift
│   ├── CaptureProcessorTests.swift
│   └── LanguageDetectionTests.swift
└── Integration/
    └── CaptureToStorageTests.swift  # End-to-end pipeline + SC-001 timing guard

Package.swift                        # SPM manifest (dependency: GRDB.swift 6.x)
```

---

## Building

### Option A — Build a DMG (recommended for distribution)

```bash
# Builds release binary, assembles .app bundle, and produces the DMG
./build-dmg.sh
# Output: .build/ClipboardVocab.dmg
```

Requires only the Swift toolchain — no Xcode GUI needed.

### Option B — Swift Package Manager (CLI, run in place)

```bash
# Clone and enter the repo
git clone <repo-url>
cd language-tool

# Resolve dependencies (downloads GRDB.swift ~6.29)
swift package resolve

# Debug build
swift build

# Release build (optimised, smaller binary)
swift build --configuration release

# Run directly (debug)
swift run

# Or run the release binary
.build/release/ClipboardVocab
```

> The built binary is a standard macOS executable. On first launch macOS may ask for Accessibility permission (required for the global ⌘ Shift C shortcut). Grant it in **System Settings → Privacy & Security → Accessibility**.

### Option C — Xcode

```bash
# Open the package in Xcode
open Package.swift
```

1. Select the **ClipboardVocab** scheme and any Mac destination.
2. Press **⌘ R** to build and run, or **⌘ U** to run tests.

To create a distributable `.app` bundle:

1. **Product → Archive** → opens Organiser.
2. **Distribute App → Direct Distribution** → exports a notarised `.app`.

> Add `LSUIElement = YES` is already set in [`Info.plist`](ClipboardVocab/App/Info.plist) — the app will not appear in the Dock.

### Option D — xcodebuild (CI / scripted)

```bash
# Build
xcodebuild \
  -scheme ClipboardVocab \
  -configuration Release \
  -destination 'platform=macOS' \
  build

# Build + run tests
xcodebuild \
  -scheme ClipboardVocab \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

---

## Running tests

```bash
# Run all tests (requires Swift toolchain only — no Xcode needed)
swift test

# Run a specific test suite
swift test --filter "VocabularyEntryRepository"
swift test --filter "CaptureProcessor"
swift test --filter "LanguageDetection"
swift test --filter "CaptureToStorage"
```

Expected output: **22/22 tests passed**.

The integration test `testCaptureLatencyWithinThreeSeconds` also enforces **SC-001**: the capture-to-DB-insert pipeline must complete in ≤ 3000 ms (it routinely runs in ~170 ms).

---

## Database

The vocabulary database is a single SQLite file stored at:

```
~/Library/Application Support/ClipboardVocab/vocabulary.sqlite
```

It is created automatically on first launch and is included in Time Machine backups.

**Inspect entries via Terminal:**

```bash
DB="$HOME/Library/Application Support/ClipboardVocab/vocabulary.sqlite"

# View all entries (most recent first)
sqlite3 "$DB" \
  "SELECT englishText, frenchTranslation, translationStatus, seenCount, firstCapturedAt
   FROM vocabulary_entries
   ORDER BY firstCapturedAt DESC;"

# Check schema version
sqlite3 "$DB" "PRAGMA user_version;"

# Count entries
sqlite3 "$DB" "SELECT COUNT(*) FROM vocabulary_entries;"
```

---

## Capture pipeline

Every clipboard change flows through this pipeline in [`CaptureProcessorService`](ClipboardVocab/Services/CaptureProcessorService.swift):

```
raw text
    │
    ├─ length > 50 chars? ──► discard (tooLong)
    │
    ├─ no natural language? ──► discard (noMeaningfulLanguage)
    │   (numbers, URLs, /unix/paths, C:\windows\paths)
    │
    ├─ NLLanguageRecognizer
    │       confidence < 0.6? ──► discard (lowConfidence)
    │       dominant ≠ English? ──► discard (notEnglish)
    │
    ├─ duplicate check
    │       exists in DB? ──► increment seenCount + lastSeenAt ──► done
    │
    └─ INSERT new entry (translationStatus = pending, seenCount = 1)
            │
            └─► TranslationService.translate()
                    success ──► update frenchTranslation, status = translated
                    failure ──► leave as pending; NWPathMonitor retries on reconnect
```

---

## Pause / Resume

- **⌘ Shift C** — global shortcut (registered via Carbon `RegisterEventHotKey`)
- **Right-click menu bar icon** → "Pause Capture" / "Resume Capture"

When paused, the timer still fires every 500 ms but clipboard reads are silently dropped. The menu bar icon switches to the paused variant. **Pause state is never persisted** — the app always starts capturing on launch.

---

## Configuration

The only user-facing configuration is the LibreTranslate endpoint, which can be changed at runtime by setting `TranslationService.libreTranslateURL`. All other settings (polling interval, confidence threshold, length gate) are compile-time constants documented in the relevant source files.

| Constant | Location | Default | Description |
|----------|----------|---------|-------------|
| Polling interval | [`ClipboardMonitorService`](ClipboardVocab/Services/ClipboardMonitorService.swift) | 500 ms | How often NSPasteboard is checked |
| Confidence threshold | [`LanguageDetectionService`](ClipboardVocab/Services/LanguageDetectionService.swift) | 0.6 | Minimum NLLanguageRecognizer confidence |
| Length gate | [`CaptureProcessorService`](ClipboardVocab/Services/CaptureProcessorService.swift) | 50 chars | Maximum eligible text length |
| Translation endpoint | [`TranslationService`](ClipboardVocab/Services/TranslationService.swift) | localhost:5001 | EN→FR HTTP endpoint (self-hosted Docker) |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 6.29.x | SQLite persistence, migrations, `ValueObservation` for live UI updates |

All other capabilities use Apple frameworks bundled with macOS:

- `NaturalLanguage` — on-device language detection (`NLLanguageRecognizer`)
- `AppKit` / `SwiftUI` — menu bar icon, popover, vocabulary list
- `Network` — `NWPathMonitor` for connectivity-restore retry
- `Carbon` — `RegisterEventHotKey` for the global keyboard shortcut

---

## Performance targets

| Metric | Target | How verified |
|--------|--------|-------------|
| Capture latency | ≤ 3 s end-to-end | `CaptureToStorageTests.testCaptureLatencyWithinThreeSeconds` |
| UI open time | ≤ 2 s | Manual — click menu bar icon |
| CPU at idle | < 1% | Manual — Activity Monitor, 10-minute run |
| RAM | < 50 MB | Manual — Activity Monitor |
| Language accuracy | > 95% for clear EN/FR | `LanguageDetectionTests` corpus |
