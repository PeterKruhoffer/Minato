# Minato

A native macOS screenshot and annotation app, written in Swift and AppKit. Capture a region, draw on it, add arrows, and pin editable text notes to specific points. No external packages or services are required.

## Run

Requires macOS 14 or later and Xcode 15 or later.

Open `Minato.xcodeproj`, select the **Minato** scheme, and press **⌘R**. The checked-in project is ready to build; XcodeGen is only needed if you change `project.yml`.

Or, from the project directory:

```sh
./scripts/run.sh
```

The app is built at `build/Build/Products/Debug/Minato.app`. Development builds use an **Apple Development** certificate from your keychain. Keep the same signing identity across rebuilds so macOS can retain Screen Recording permission. The project is configured for the development team available on this Mac; on another Mac, select your own team in Signing & Capabilities and update `DEVELOPMENT_TEAM` in `project.yml`. If needed, configure your Apple account/certificate in Xcode → Settings → Accounts. To distribute the app to other Macs, configure your Developer ID and notarization in Xcode.

For a machine without a development certificate, `MINATO_CODE_SIGN_IDENTITY=- ./scripts/run.sh` permits an ad-hoc build, but screen-recording access may need to be granted again after each rebuild. To select a specific installed identity, set `MINATO_CODE_SIGN_IDENTITY` to its name or fingerprint.

Normal app builds produce one executable and one app signing operation. SwiftUI preview dylibs are disabled because this app uses AppKit. If Keychain asks whether `codesign` may use the Apple Development private key, **Allow** authorizes a single signing operation; **Always Allow** authorizes that tool to reuse that key for future builds. Make this choice in the macOS dialog; no password belongs in a build script. Unit-test builds also sign the test bundle.

If password prompts continue after **Always Allow**, the signing key’s partition list may still exclude Apple’s signing tools, even when `codesign` appears under Access Control. This is a separate Keychain rule. Repair only the private key associated with the active certificate, add the missing `apple:` partition, and preserve its existing trusted applications and other partition entries. Keys can share the same display name, so identify the key by its certificate fingerprint. See [Apple’s signing-access troubleshooting guide](https://developer.apple.com/forums/thread/712005). This is a one-time Keychain repair; do not store your login password in build scripts.

If permission is enabled but capture is denied after updating from an ad-hoc build:

1. Export any sample edits you want to keep, then fully quit Minato with **⌘Q**.
2. Open **System Settings → Privacy & Security → Screen & System Audio Recording**, and turn Minato off and on.
3. Reopen the newly built app at `build/Build/Products/Debug/Minato.app` and try a capture.
4. If macOS still associates the permission with the old build, quit Minato and reset only its Screen Recording record with `tccutil reset ScreenCapture com.minato.desktop`. Reopen Minato, start a capture, and grant permission again. This does not reset other apps’ permissions. “System Audio Recording Only” is not needed for screenshots.

The app delegates permission checks to ScreenCaptureKit and shows access guidance only when the capture API actually reports a permission denial. See [Apple’s explanation of ad-hoc signing and screen-capture permissions](https://developer.apple.com/forums/thread/819406).

## Use

- Press **⇧⌘2** from any app, then drag to select a region. **Esc** cancels. Change the shortcut in **Minato → Settings** or by clicking the shortcut at the bottom of the sidebar.
- macOS requests **Screen & System Audio Recording** permission on the first capture. Enable Minato in **System Settings → Privacy & Security**, then relaunch if macOS asks. Minato captures still images only.
- Choose **Draw (P)**, **Arrow (A)**, or **Note (T)**. Click with the Note tool to pin text to that point; **⌘Return** saves the note. Notes support up to 500 characters.
- Use **Select (V)** to move annotations. Double-click a note on the canvas or in the annotation list, or select it and press **Return**, to edit its text. **Delete** removes the selected annotation. Color and stroke controls also apply to the selection.
- Hold **Shift** while drawing an arrow to snap its angle. Hold Shift with Draw for a straight stroke.
- New arrows automatically cycle through the six palette colors. The **Next arrow color** swatch previews the next one. Choose a swatch to override the next arrow, or select an existing arrow to recolor it manually. Moving an arrow keeps its color; drawing and notes keep the color you chose.
- **⌘Z / ⇧⌘Z** undo and redo. **⌘C** copies the annotated image when the canvas is focused. **⇧⌘C** always copies the image. **⌘S** exports a PNG at the original pixel resolution.
- **⌘O** opens an existing image. **⌘V** pastes an image from the clipboard when the canvas is focused.
- **Fit (⌘0)** shows the whole image. **100% (⌘1)** shows one image pixel per display pixel, including after resizing; scroll or use a trackpad to pan a larger image.
- Resize the sidebar and inspector by dragging their dividers. **View → Hide Sidebar (⌃⌘S)** and **Hide Inspector (⌥⌘I)** make more room for the image. Use **View → Customize Toolbar…** to choose your toolbar actions.
- Navigate captures or annotations with the arrow keys. **⌥⌘1 / ⌥⌘2 / ⌥⌘3** focus the canvas, capture list, or annotation list. On the canvas, arrow keys move a selected annotation by one image pixel; **Shift** moves it by ten. **Tools → Add Note at Center… (⌥⌘N)** creates a note without pointing at the image.
- Close the editor to keep Minato in the menu bar with the global shortcut active. **⌘Q** fully quits.

The sample capture is a practice canvas and is not saved in history. Copy or export it to keep your edits. Real captures and imported images save automatically under `~/Library/Application Support/Minato/Captures`, with the original image and editable annotations stored separately. Undo history lasts for the current app session. **File → Delete Capture** removes a saved capture after confirmation.

Captures are local to this Mac. The app has no network code, analytics, or account system. A selection is confined to one display; multi-monitor setups get a picker on each display.

## Develop and test

```sh
./scripts/build.sh
xcodebuild -project Minato.xcodeproj -scheme Minato \
  -configuration Debug -derivedDataPath build test
```

The tests cover annotation undo/redo, persistence, PNG resolution and orientation, appearance-independent exports, stroke hit testing, callout placement, Retina crops, arrow color cycling, keyboard movement, actual-size zoom during resizing, and split-pane layout.

Source layout:

- `AppDelegate.swift` — application lifecycle, native menus, menu bar item, settings.
- `ScreenCapture.swift` — ScreenCaptureKit snapshots and region selection overlays.
- `ShortcutManager.swift` — registered global shortcut and shortcut recorder.
- `EditorController.swift` / `WorkspaceView.swift` / `EditorToolbar.swift` — editor actions, native split panes and tables, customizable toolbar, notes, export.
- `CanvasView.swift` / `AnnotationRenderer.swift` — editing gestures and shared screen/export rendering.
- `Models.swift` — editable annotations, undo history, local capture storage.

The capture implementation uses Apple’s [ScreenCaptureKit screenshot API](https://developer.apple.com/videos/play/wwdc2023/10136/). The registered Carbon hotkey does not require Accessibility or Input Monitoring permission.

## macOS interface

Minato uses AppKit’s window toolbar, split-view sidebar and inspector, table selection, segmented controls, and standard buttons. The interface follows the Mac’s appearance and accent color; screenshots and exported annotations keep their original colors. See [the interface review](docs/apple-interface-review.md) for the Apple Human Interface Guidelines applied to this design.
