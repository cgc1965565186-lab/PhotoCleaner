# JingYu · iPhone Photo Organizer

[简体中文](README.md) | **English**

A SwiftUI + PhotoKit app built for personal iPhone use, targeting iOS 18 and later. Every analysis runs entirely on-device — no media is ever uploaded, no accounts, no analytics.

- Similar-photo detection is powered by perceptual hashing (dHash) with BK-Tree grouping; duplicate checking never reads media content
- Fully open source under MIT, with unit tests covering the core algorithms — forks and PRs are welcome

## Quick Start

1. `git clone` this repository and open `PhotoCleaner.xcodeproj` in Xcode
2. Select the PhotoCleaner target → Signing & Capabilities → enable "Automatically manage signing" and choose your own team (a free personal Apple ID works)
3. Connect your iPhone, pick the device, and press ⌘R
4. On first launch, tap "Start Smart Scan" on the Organize tab

Note: the project ships without a development team, so step 2 is required after cloning. Provisioning profiles from free accounts expire every 7 days — just run again to refresh.

## Features & Structure

Three tabs, with all secondary pages pushed onto a single navigation stack:

- **Organize**: device capacity and library overview, smart scan entry, and a review checklist (exact duplicates / visually similar / burst groups / screenshots / Live Photos / videos), each pushing to a dedicated result page
- **Library**: full library browsing with grid/list toggle, sorting and filtering, and multi-select deletion; tap a thumbnail to open the detail page
- **Settings**: permission status, privacy notes, and local index management

- Duplicate detection: dHash perceptual hashing + BK-Tree candidate grouping; a pair is "exact duplicate" when byte size, pixel dimensions, and hash all match
- Detail page: large-image preview, full metadata, add-to-delete-list
- Duplicate groups support a "Keep recommended only" one-tap selection
- Handles both full and limited PhotoKit access; scanning only runs when the user explicitly starts it
- Interrupted scans keep their progress; rescans reuse the local index

## Performance Design

- File sizes come from PhotoKit resource metadata (key-value access on `PHAssetResource`) — **no media content is read and no original files are downloaded**; a library of tens of thousands of items is measured in seconds
- Similarity detection only reads system thumbnails (192px), with fingerprints computed on 4 concurrent tasks
- Grouping and duplicate checks run off the main thread; the main thread only receives batched results
- Scan progress is throttled to whole-percent updates to avoid high-frequency view invalidation
- Thumbnails use `PHCachingImageManager` plus an in-memory cache, with request resolution scaled by the display scale

## Building

Open `PhotoCleaner.xcodeproj` in Xcode. The deployment target is iOS 18, with automatic signing and a personal development team.

Command-line device build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -configuration Debug -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -allowProvisioningUpdates -derivedDataPath /tmp/PhotoCleanerDevice build
```

Install and launch:

```sh
xcrun devicectl device install app --device <DEVICE_UDID> /tmp/PhotoCleanerDevice/Build/Products/Debug-iphoneos/PhotoCleaner.app
xcrun devicectl device process launch --device <DEVICE_UDID> app.codex.jingyu
```

### Known Environment Patch

On macOS 27.2, Xcode 27.1 fails to launch the Swift macro plugin service due to a nested-sandbox denial (`sandbox-exec: sandbox_apply: Operation not permitted`), which breaks compilation of `@Observable` / `@Model`. The Debug/Release configurations add `OTHER_SWIFT_FLAGS = -Xfrontend -disable-sandbox` as a workaround; remove it once you upgrade to Xcode 27.2 or later.

## Algorithm Unit Tests

```sh
swift test --disable-sandbox --scratch-path /tmp/PhotoCleanerPackageBuild
```

## Notes

Similarity groups are review suggestions only. Recommended keepers are never pre-selected, the app never deletes photos automatically, and it never touches system caches or other apps' data. Provisioning profiles from free developer accounts expire every 7 days — rebuild and reinstall to refresh.

This project is open sourced under the MIT license — see [LICENSE](LICENSE). Issues and pull requests are welcome.
