# Changelog

All notable changes to GameBoyKit are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project follows [SemVer](https://semver.org/).

## [Unreleased] — 0.5.0 polish pass

### Added
- **`CartridgeScores`** in ConsoleKit — `UserDefaults`-backed best-score persistence keyed by cartridge × mode. Snake, Lander (4 modes), and Hopper (4 modes) all surface BEST on the mode-select briefing and a "NEW BEST!" flag on result banners. Keys live under `gameboykit.score.` prefix with case-normalized cartridge + mode strings.
- **`CameraShake`** in ConsoleKit — `Sendable` value-type screen-shake helper. State triggers on impact events with amplitude + tick count; view applies `offsetX` / `offsetY` via SwiftUI's `.offset` modifier. Wired into Lander crashes (amplitude scales with impact magnitude) and Hopper deaths (gentler shake for cone-spot deaths, harder for physical hits).
- **`ParticleSystem`** in ConsoleKit — `Sendable` value-type one-shot particle burst helper. Each particle integrates position + velocity + gravity + drag and culls on life expiry. Wired into Lander touchdowns (all 4 modes — origin point varies per mode so Pendulum's burst comes from the cargo, not the ship) and Hopper goal-reached celebrations.
- **Title-screen art** for LANDER (hero lander sprite with flickering thrust flame) and HOPPER (frog on a lily pad with scrolling water ripples).
- **CHANGELOG.md** — this file.

### Changed
- Cave Dive cave generation now seeds six independent random sine phase offsets per run, so each dive is visually distinct. Amplitudes + frequencies stay fixed so wall-bounds + minimum-passage-width guarantees hold.
- Title-screen `PRESS A` pulse nudged from `y=116` → `y=130` in both LANDER and HOPPER to clear the new hero sprites.
- README updated for the four-cart catalog + shared-services documentation; chassis ASCII art shows `mvBOY` / `MV ®` instead of the older `CLINGY BOY` / `travis ®`.

## [0.4.1] — 2026-05-11

### Fixed
- **`B: MENU` exit from paused run** for Lander and Hopper. Previously the only way out of a paused run was to resume + intentionally die, or to tap the chassis MENU button (which bailed all the way to the cartridge shelf, not the mode-select inside the cartridge). `exitToModeSelect()` in both states now also accepts `.paused`. PAUSED banner subtitle updated to advertise `A: RESUME  B: MENU`.

## [0.4.0] — 2026-05-11

### Added
- **HOPPER cartridge** — a road-and-river crossing game with a four-mode select grid. Named HOPPER (not "Frogger") for IP cleanliness — Frogger is a Konami trademark.
  - **CLASSIC** — vanilla Frogger-style. 5 river lanes + 4 road lanes + sidewalk. 3 lives, 30s timer.
  - **ENDLESS** — Crossy-Road-style infinite upward climb with auto-scrolling camera, procedurally-generated lanes, and one-life score-chasing.
  - **NIGHT SHIFT** — Classic layout with a smooth ~0.5s day/night fade cycle. Night phase reveals only a 7×5 cell lantern around the frog; car headlights cut through the dark; traffic slows to 65%.
  - **HEIST** — Stealth puzzle. Four patrol corridors with guards projecting 4-cell vision cones. Slip between the cones to reach the vault.

### Architecture
- Reused the LANDER cartridge's per-mode tick-dispatcher pattern. `LaneKind.safe` (for Endless's procgen grass strips) and `LaneKind.patrol` (for Heist's guards) join `.road` and `.river`. `Entity.facing` field added (only meaningful for patrol guards). New `DeathCause` cases `.fellBehind` (Endless) and `.spotted` (Heist).

## [0.3.0] — 2026-05-11

### Added
- **LANDER cartridge** — a multi-mode Lunar Lander suite with a four-mode select grid mirroring QuestKid's dungeon select.
  - **CLASSIC** — vanilla Lunar Lander. Gravity, thrust, fuel, soft touchdown.
  - **PENDULUM** — Cargo crate hangs on a fixed-length tether below the ship. The cargo (not the ship) is what has to land softly. Rapid lateral reversals whip the rope — flip too aggressively and it snaps.
  - **MAIL RUN** — Three pads scattered at varying heights. Deliver to each in sequence under a 60-second clock, on a single shared fuel tank.
  - **CAVE DIVE** — Procedurally-generated vertical cave (~6.7 screen-heights). Asymmetrically-undulating walls; camera scrolls to follow.
- In-LCD HUD helpers: **SAFE** badge (mode-aware — uses cargo velocity in Pendulum), flashing VY readout when over the safe-landing threshold, alignment beam projecting up from the current target pad.

### Architecture
- Root `@Observable` state machine: `title → modeSelect → playing → (paused | landed | crashed)`. Per-mode tick variants (`classicTick`, `pendulumTick`, `mailRunTick`, `caveDiveTick`) share `stepShipPhysics`. Multi-pad geometry as a first-class `Pad` struct.

## [0.2.1] — 2026-05-11

### Changed
- `GameBoyView`'s top edge gains a **20pt continuous-style squircle** so the face reads as a contained device face instead of a hard horizontal line meeting the host's nav bar. Matches the iPhone's own hardware corner radius. Bottom corners stay sharp — the immersive bottom bleed from 0.2.0 is preserved.

## [0.2.0] — 2026-05-11

### Changed
- **Full-bleed face**: `GameBoyView` now paints the host's screen as the Game Boy face, edge-to-edge, instead of rendering as a framed plastic object floating on a backdrop. Dropped `.aspectRatio(0.52)` and `.frame(maxWidth: 520)`; the face fills `maxWidth × maxHeight` of whatever the host gives it.
- Gradient ignores the **bottom** safe area only — the cream paints under the home indicator for an immersive bleed, but stops cleanly at the top safe-area edge so a host `NavigationStack`'s nav bar stays its default appearance.
- Internal layout uses flex `Spacer`s instead of fixed-pixel gaps so controls sink into the lower third on tall screens.

### Migration
- Hosts wrapping `GameBoyView` in padded backdrop containers need to drop those wrappers. See `GameBoyKitDemo/ContentView.swift` for the recommended hosting shape.

## [0.1.0] — 2026-05-11

### Added
- Initial public release. Three SPM libraries (GameBoyKit / ConsoleKit / CartridgeKit).
- **Snake** cartridge.
- **QuestKid** cartridge with 7 dungeons spelling S-H-E-L-B-Y on a heart-shaped dungeon-select map, per-dungeon themes, boss with telegraphed attacks, persistent per-dungeon clear records.
- Mode-select / pause / device-menu (palette + theme + about + input test + exit-to-library).
- 10 paired light/dark palette sets (dmgMeetsColor / classicDMG / atomicRed / oceanBlue / mint / pink / yellow / orange / purple / black).
- Root `Package.swift`, MIT `LICENSE`, `README.md`.

[Unreleased]: https://github.com/scalecode-solutions/GameBoyKit/compare/0.4.1...HEAD
[0.4.1]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.4.1
[0.4.0]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.4.0
[0.3.0]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.3.0
[0.2.1]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.2.1
[0.2.0]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.2.0
[0.1.0]: https://github.com/scalecode-solutions/GameBoyKit/releases/tag/0.1.0
