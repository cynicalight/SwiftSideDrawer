# SideDrawer

A lightweight SwiftUI side drawer (hamburger menu) container. The whole main
page slides over a full-screen menu as one rigid unit — safe areas included —
with screen-matched rounded corners, interactive spring tracking, flick-to-toggle,
and an edge-pull gesture.

## Preview

https://github.com/user-attachments/assets/71d607c8-4e20-4003-84ce-ff6a0cfa9cd9


## Requirements

- iOS 17+
- SwiftUI

## Installation (Swift Package Manager)

### Xcode
File ▸ Add Package Dependencies… ▸ enter the repository URL (or, for a local
copy, "Add Local…" and pick the `SideDrawer` folder).

### Package.swift
```swift
dependencies: [
    .package(url: "https://github.com/<you>/SideDrawer.git", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["SideDrawer"])
]
```

## Usage

```swift
import SwiftUI
import SideDrawer

struct RootView: View {
    @State private var isMenuOpen = false

    var body: some View {
        SideDrawerContainer(isOpen: $isMenuOpen) {
            // Menu (sits underneath, full screen)
            ZStack {
                Color.orange.ignoresSafeArea()
                Text("Menu").font(.largeTitle.bold()).foregroundStyle(.white)
            }
        } content: {
            // Main page (slides over the menu)
            NavigationStack {
                Text("Main")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6))
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { isMenuOpen.toggle() } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                        }
                    }
            }
        }
    }
}
```

## Parameters

| Parameter        | Default     | Description                                                   |
|------------------|-------------|---------------------------------------------------------------|
| `isOpen`         | —           | Two-way binding controlling open/closed state.                |
| `edge`           | `.leading`  | Side the drawer slides from (`.leading` / `.trailing`).       |
| `menuWidthRatio` | `0.8`       | How far the main page slides, as a fraction of screen width.  |
| `edgeWidth`      | `24`        | Width of the edge band that pulls the drawer open when closed.|
| `cornerRadius`   | `nil`       | Main-page corner radius. `nil` matches the device screen.     |
| `menu`           | —           | The drawer view (full-screen layer underneath).               |
| `content`        | —           | The main page view (slides over the menu).                    |

## Interaction

- Tap the hamburger button (drives `isOpen`) to open/close.
- Drag from the screen edge to pull the drawer open.
- Drag or tap the main page to close.
- A flick toggles via velocity prediction.

## Example

A runnable demo lives in `Examples/SideDrawerDemo`. Open
`Examples/SideDrawerDemo/SideDrawerDemo.xcodeproj` and run — it depends on this
package locally (`XCLocalSwiftPackageReference "../.."`), so it always builds
against the current source.

## Corners

The main page rounds with `ContainerRelativeShape`, which is concentric with its
container — no private API. On iOS 26 the window provides a container shape that
matches the device screen, so the corners match automatically. On older systems
the container shape may not reflect the physical screen; if the corners don't
match there, pass an explicit `cornerRadius:` value.
