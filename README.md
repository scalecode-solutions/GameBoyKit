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
│               mvBOY ™                   │
│                                         │
│    ▲                                    │
│  ◄ ● ►          ●  ●                    │
│    ▼          ─B─ ─A─                   │
│                                         │
│             ───── ─────                 │
│             SELECT  START               │
│                                         │
│ MV ®                                ▌▌▌ │
└─────────────────────────────────────────┘
```

The repo ships **three SPM libraries** that build on each other:

| Library | What it is |
|---|---|
| **GameBoyKit** | The chassis — `GameBoyView`, the D-pad/A/B/Start/Select/MENU input model, the on-chassis power slider, palette + theming + device settings. |
| **ConsoleKit** | The "OS" — `GameBoyCartridge` value type, `CartridgeShelf` (boot → menu → playing state machine), `PixelCanvas` for in-LCD rendering, `DeviceMenu` system overlay, plus shared services (`CartridgeScores` for persisted best scores, `CameraShake` and `ParticleSystem` for game-feel effects). |
| **CartridgeKit** | Built-in games — **Snake**, **QuestKid** (Zelda-likes with 7 dungeons), **Lander** (physics suite, 4 modes), **Hopper** (road-and-river crossing, 4 modes). |

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/scalecode-solutions/GameBoyKit.git", from: "0.5.0")
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
import CartridgeKit  // for .snake, .questKid, .lander, .hopper

GameBoyView(
    screen: { input in
        CartridgeShelf(
            input: input,
            cartridges: [
                .snake,
                .questKid,
                .lander,
                .hopper,
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
        ┌─────────┴──────────┐
        │                    │
        ▼                    ▼
  ┌────────────┐       ┌──────────┐
  │CartridgeKit│ ────► │ConsoleKit│
  │ (games)    │       │ (cart    │
  │            │       │  format, │
  │ Snake      │       │  shelf,  │
  │ QuestKid   │       │  pixel   │
  │ Lander     │       │  canvas, │
  │ Hopper     │       │  effects)│
  └────────────┘       └────┬─────┘
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

### Snake
Classic arcade. D-pad turns, eat dots, don't hit yourself. ~6 ticks/sec at start, speeds up with each apple. Best score persists across runs.

### QuestKid
A tiny Zelda-likes adventure with:
- Tutorial dungeon (open meadow + a real dungeon with locked door + boss + secret heart vault)
- 6 letter-shape dungeons spelling **S-H-E-L-B-Y** when traced on the dungeon-select map
- The dungeon select map itself traces a heart silhouette
- Per-dungeon theming (serpentine / ruins / caverns / library / boneyard / grove)
- Boss with telegraphed attacks (fan shot + charge, enrage at half HP)
- Persistent per-dungeon clear records

### Lander
Multi-mode Lunar Lander suite. Mode-select grid mirrors QuestKid's dungeon select. **Four flights:**

| Mode | The twist |
|---|---|
| **CLASSIC** | Vanilla Lunar Lander. Gravity, thrust, fuel, soft touchdown. |
| **PENDULUM** | Cargo crate hangs on a fixed-length tether below the ship. The cargo (not the ship) is what has to land softly. Rapid lateral reversals whip the rope — flip too aggressively and it snaps. |
| **MAIL RUN** | Three pads scattered at varying heights. Deliver to each in sequence under a 60-second clock, on a single shared fuel tank. |
| **CAVE DIVE** | Procedurally-generated vertical cave (~6.7 screen-heights, fresh seed per run). Walls undulate asymmetrically; camera scrolls to follow. Soft landing on the bottom-chamber pad wins. |

In-LCD feedback: a **SAFE** badge lights up when current velocity components would qualify as a soft landing (mode-aware — uses ship velocity in Classic/MailRun/CaveDive, cargo velocity in Pendulum); the VY readout flashes red when descending faster than the safe threshold; an alignment beam glows from the pad up when you're horizontally over the current target.

### Hopper
Multi-mode road-and-river crossing game. Mode-select grid; four modes:

| Mode | The twist |
|---|---|
| **CLASSIC** | Vanilla Frogger-style. 5 river lanes + 4 road lanes + sidewalk. 3 lives, 30s timer, reach the top to win. |
| **ENDLESS** | Crossy-Road-style infinite upward climb. Camera auto-scrolls upward; procedurally-generated lanes (rivers / roads / safe grass) appear above. One life, score = rows climbed. |
| **NIGHT SHIFT** | Classic layout, but the playfield cycles through day and night with a smooth ~0.5s dusk/dawn fade. Night phase reveals only a 7×5 cell lantern around the frog; car headlights cut through the dark; traffic slows to 65%. |
| **HEIST** | Stealth puzzle. Four patrol corridors with guards walking back-and-forth, each projecting a 4-cell vision cone in their facing direction. Slip between the cones to reach the vault. |

Named HOPPER (not "Frogger") for IP cleanliness — Frogger is a Konami trademark.

## Shared services (ConsoleKit)

Beyond the cartridge format and shelf, ConsoleKit provides three small reusable services that the built-in games use and consumer games can embed too:

- **`CartridgeScores`** — `UserDefaults`-backed per-cartridge × per-mode high-score persistence. Snake, Lander, and Hopper all use this to surface "BEST X" on their mode-select briefings and a "NEW BEST!" flag on result banners.
- **`CameraShake`** — value-type screen-shake helper. State calls `trigger(amplitude:ticks:)` on impact events; view applies `offsetX`/`offsetY` via SwiftUI's `.offset` modifier.
- **`ParticleSystem`** — value-type one-shot particle burst helper. Used by Lander touchdowns and Hopper goal-reached celebrations.

All three are `Sendable` value types meant to be nested inside `@Observable` state classes.

## License

MIT — see [LICENSE](LICENSE).
