# Native macOS Suite for Facebook: Messenger, Marketplace & Groups

Three standalone, lightweight native macOS desktop applications written in **Swift 6** (`AppKit`, `SwiftUI`, and `WebKit`)—each with its own bundle identifier, Retina squircle app icon, menu bar icon, distraction-free UI, and tailored keyboard shortcuts:

1. **Messenger.app**: Standalone Facebook Messenger desktop app (`facebook.com/messages` & `messenger.com`) with native macOS notifications, sender avatars, unread Dock & menu bar badges, and dedicated voice/video call windows.
2. **Marketplace.app**: Standalone Facebook Marketplace desktop app with a native `.unifiedCompact` macOS toolbar (`Browse`, `Buying`, `Selling`, `Saved`, `Inbox`, `+ Sell`, `Search`, `Copy Clean Link`), zero News Feed/Reels clutter, and in-app buyer/seller messaging.
3. **Groups.app**: Standalone Facebook Groups desktop app with a native `.unifiedCompact` macOS toolbar (`Feed`, `Your Groups`, `Discover`, `New Post`, `Search`, `Copy Clean Link`), photo lightbox & group file downloads, and zero News Feed/Reels clutter.

---

## Features

- **Distraction-Free Native Experience**: Strips Facebook's global top navigation bar, right-hand sponsored rails, floating chat heads, and News Feed/Reels distractions so each app feels purpose-built for macOS.
- **Menu Bar & Background Mode (`⌘W`)**: Closing the main window hides the app to the background/menu bar while keeping notifications and unread badges active (configurable in `⌘,` Settings).
- **Unread Badges & Rich Notifications**: Observes live conversation state changes and Web Notifications to display native macOS Notification Center alerts (with sender avatars) and accurate Dock + menu bar unread counts.
- **Smart URL Routing**: Keeps login, 2FA, Messenger threads, Marketplace listings, Group posts, photo lightboxes, and voice/video calls inside the app while routing external web links to your default browser.
- **Clean Link Sharing (`⇧⌘C`)**: Copies the current Marketplace listing or Group post URL with Facebook tracking parameters (`__cft__`, `__tn__`, `fbclid`, `referral_code`, etc.) automatically stripped.

---

## Keyboard Shortcuts

| Shortcut | Messenger | Marketplace | Groups |
|----------|-----------|-------------|--------|
| `⌘N` | New Message | Create New Listing (`+ Sell`) | New Post in Current Group |
| `⇧⌘N` | — | — | Create New Group |
| `⌘F` | Search Chats | Search Marketplace | Search Groups |
| `⌘1`–`⌘9` | Jump to Chat 1–9 | `⌘1` Browse · `⌘2` Buying · `⌘3` Selling · `⌘4` Saved · `⌘5` Inbox | `⌘1` Feed · `⌘2` Your Groups · `⌘3` Discover |
| `⇧⌘C` | — | Copy Clean Listing Link (no tracking params) | Copy Clean Group/Post Link |
| `⇧⌘O` | — | Open Current Page in Browser | Open Current Page in Browser |
| `⌘[` / `⌘]` | Back / Forward | Back / Forward | Back / Forward |
| `⌘+` / `⌘-` / `⌘0` | Zoom In / Out / Reset | Zoom In / Out / Reset | Zoom In / Out / Reset |
| `⌘W` | Hide to Background / Menu Bar | Hide to Background / Menu Bar | Hide to Background / Menu Bar |
| `⌘,` | Settings | Settings | Settings |

---

## Build & Install

Requirements: **macOS 15.0+** and **Xcode 16+**.

```bash
# Build all three Release apps into ./build/ (Messenger.app, Marketplace.app, Groups.app)
./scripts/build.sh

# Or build a single app
./scripts/build.sh Messenger
./scripts/build.sh Marketplace
./scripts/build.sh Groups

# Build & install all three to /Applications (or ~/Applications)
./scripts/build.sh --install

# Launch
open build/Messenger.app
open build/Marketplace.app
open build/Groups.app
```

### Optional: Sign with Your Apple Developer Team ID

By default, the project builds with ad-hoc code signing (`CODE_SIGN_IDENTITY = -`) so anyone can build and run out of the box. To sign with your own Apple Development certificate (which preserves macOS Notification Center permissions across rebuilds):

```bash
cp Local.xcconfig.example Local.xcconfig
# Edit Local.xcconfig with your BUNDLE_ID_PREFIX and DEVELOPMENT_TEAM
```

`Local.xcconfig` is gitignored and automatically loaded by [`Messenger/Config/Base.xcconfig`](Messenger/Config/Base.xcconfig).

### Running Tests

Run `./scripts/test.sh` (or `⌘U` in `Messenger.xcodeproj`) to run the Swift Testing unit test suite across all three apps.

---

## Acknowledgments

Inspired by open-source macOS Messenger wrappers including [Goofy](https://github.com/danielbuechele/goofy) by Daniel Büchele and [Messenger for macOS](https://github.com/Paksonite/messenger) by Paksonite.

## License

Released under the [MIT License](LICENSE).
