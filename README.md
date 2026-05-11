# GameBoyKit

SwiftUI Game Boy mockup you can host real games inside. Pixel-perfect DMG silhouette × Game Boy Color palette, 8-way D-pad, A/B/Start/Select/Menu input, full-color theming, on-chassis power slider, light/dark mode aware.

```
┌─────────────────────────────────────────┐
│ ◁OFF [▓] ON▷           ╭─ MENU ─╮       │
│  POWER                 ╰────────╯       │
│   ╔═══════════════════════════════════╗ │
│   ║                                   ║ │
│   ║          your game here           ║ │
│   ║                                   ║ │
│   ╚═══════════════════════════════════╝ │
│              CLINGY BOY ™               │
│                                         │
│    ▲                                    │
│  ◄ ● ►          ●  ●                    │
│    ▼          ─B─ ─A─                   │
│                                         │
│             ───── ─────                 │
│             SELECT  START               │
│                                         │
│ travis ®                            ▌▌▌ │
└─────────────────────────────────────────┘
```

The repo ships **three SPM libraries** that build on each other:

| Library | What it is |
|---|---|
| **GameBoyKit** | The chassis — `GameBoyView`, the D-pad/A/B/Start/Select/MENU input model, the on-chassis power slider, palette + theming + device settings. |
| **ConsoleKit** | The "OS" — `GameBoyCartridge` value type, `CartridgeShelf` (boot → menu → playing state machine), `PixelCanvas` for in-LCD rendering, `DeviceMenu` system overlay. |
| **CartridgeKit** | Built-in games — **Snake** (classic) and **QuestKid** (a Zelda-likes adventure with 7 dungeons, secret rooms, themed visuals). |

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/scalecode-solutions/GameBoyKit.git", from: "0.1.0")
```

And depend on whichever libraries you need:

```swift
.product(name: "GameBoyKit",   package: "GameBoyKit"),
.product(name: "ConsoleKit",   package: "GameBoyKit"),
.product(name: "CartridgeKit", package: "GameBoyKit"),
```

Or in Xcode: **File ▸ Add Package Dependencies… ▸** paste the repo URL.

**Requirements:** iOS 18+, macOS 15+, Swift 6.

## Quickstart — drop a Game Boy on screen

```swift
import SwiftUI
import GameBoyKit

struct ContentView: View {
    @State private var poweredOn = true
    var body: some View {
        GameBoyView(
            screen: { input in
                // Your view here. `input` is an @Observable
                // GameBoyInput exposing dpad, aPressed, bPressed,
                // startPressed, selectPressed, menuPressed +
                // an AsyncStream<ButtonEvent> of edge-triggered events.
                MyGameView(input: input)
            },
            headline: { Text("MY GAME") },
            subtitle: { Text("DOT MATRIX • TAP TO PLAY") },
            brand:    { Text("by you ®") },
            powerOn:  $poweredOn,
            palette:  .dmgMeetsColor   // or .classicDMG, .atomicRed, …
        )
    }
}
```

## Use the cartridge system

If you want the full boot-screen → cartridge-select → playing flow, use `ConsoleKit`:

```swift
import GameBoyKit
import ConsoleKit
import CartridgeKit  // for .snake, .questKid

GameBoyView(
    screen: { input in
        CartridgeShelf(
            input: input,
            cartridges: [
                .snake,
                .questKid,
                GameBoyCartridge(
                    id: "mygame",
                    title: "MY GAME",
                    blurb: "A SHORT DESCRIPTION",
                    make: { input in MyGameView(input: input) }
                )
            ]
        )
    }
)
```

`CartridgeShelf` handles boot splash, the cartridge select menu, in-game MENU button → system overlay (COLOR / THEME / HAPTICS / ABOUT / INPUT TEST / EXIT TO LIBRARY), and routing back to the menu when each game ends.

## Theming

Built-in palette sets (each has matched light/dark variants):

| ID | Look |
|---|---|
| `dmgMeetsColor` | Cream shell, berry A/B (default) |
| `classicDMG` | Gray DMG, dark gray buttons |
| `atomicRed` | Coral shell, gold A/B |
| `oceanBlue` | Sky blue shell, coral A/B |
| `mint` | Pastel mint, magenta A/B |
| `pink` | Bubblegum, mint A/B |
| `yellow` | Sunny, violet A/B |
| `orange` | Tangerine, cyan A/B |
| `purple` | Lavender, gold A/B |
| `black` | Stealth black, electric red A/B |

End users can also change theme at runtime via the on-device menu (MENU button → COLOR / THEME items). Settings persist to `UserDefaults`.

## Architecture

```
┌────────────────────────────────────────────────────┐
│  Your app                                          │
│  ├─ GameBoyView { screen: { input in … } }         │
│  └─ Could host:                                    │
│     ├─ A single view (basic)                       │
│     └─ CartridgeShelf with multiple cartridges     │
└─────────────────┬──────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
  ┌──────────┐         ┌──────────┐
  │CartridgeKit│ ───►  │ConsoleKit│
  │ (games)   │        │ (cartridge│
  │           │        │  format,  │
  │ Snake     │        │  shelf,   │
  │ QuestKid  │        │  pixel    │
  │           │        │  canvas)  │
  └──────────┘         └─────┬────┘
                             │
                             ▼
                       ┌──────────┐
                       │GameBoyKit│
                       │ (chassis,│
                       │  input,  │
                       │  palette)│
                       └──────────┘
```

Dependency direction: `CartridgeKit → ConsoleKit → GameBoyKit`. Each layer reusable on its own.

## The included games

**Snake** — classic. D-pad turns, eat dots, don't hit yourself. ~6 ticks/sec at start, speeds up with each apple.

**QuestKid** — a tiny Zelda-likes adventure with:
- A tutorial dungeon (open meadow + a real dungeon with locked door + boss + secret heart vault)
- 6 letter-shape dungeons spelling S-H-E-L-B-Y when traced on the dungeon-select map
- The dungeon select map itself traces a heart silhouette
- Per-dungeon theming (serpentine, ruins, caverns, library, boneyard, grove)
- Boss with telegraphed attacks (fan shot + charge, enrage at half HP)
- Persistent per-dungeon clear records

## License

MIT — see [LICENSE](LICENSE).
