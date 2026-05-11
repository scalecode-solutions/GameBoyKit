import Foundation

// MARK: - Geometry

enum QuestKidLayout {
    /// Tile size in logical LCD pixels. 16×16 gives us a tidy 16×9
    /// grid on our 256×144 LCD, with the top tile-row reserved for HUD.
    static let tileSize: Int = 16
    /// Tile grid dimensions for a single room (playable area only).
    static let roomCols: Int = 16
    static let roomRows: Int = 8        // rows 0..<8; rendered below the HUD
    /// Top-of-screen HUD strip — 16px (one tile row).
    static let hudHeight: Int = 16

    /// Pixel y-offset where the playable tile grid starts.
    static var playYOffset: Int { hudHeight }
    /// Pixel dimensions of the full playable area.
    static var playWidth:  Int { roomCols * tileSize }     // 256
    static var playHeight: Int { roomRows * tileSize }     // 128 (+16 HUD = 144)
}

// MARK: - Tiles

enum TileKind: Sendable, Hashable {
    case grass          // walkable, default floor
    case sand           // walkable, lighter floor
    case stone          // dungeon floor — walkable, dark slate
    case rock           // wall
    case tree           // wall
    case water          // wall (can't cross)
    case wallDark       // dungeon wall — different visual from overworld rock
    case door(Direction)             // walkable; triggers room transition
    case lockedDoor(Direction)       // blocks until player has a key
    case secretPassage(Direction)    // looks like a wall, walkable, transitions like a door

    var isSolid: Bool {
        switch self {
        case .grass, .sand, .stone, .door, .secretPassage: return false
        case .rock, .tree, .water, .wallDark: return true
        case .lockedDoor: return true   // gated check happens in state with hasKey
        }
    }
}

enum Direction: CaseIterable, Sendable, Hashable {
    case up, down, left, right

    var opposite: Direction {
        switch self {
        case .up:    return .down
        case .down:  return .up
        case .left:  return .right
        case .right: return .left
        }
    }

    var dx: Double { self == .left ? -1 : self == .right ? 1 : 0 }
    var dy: Double { self == .up   ? -1 : self == .down  ? 1 : 0 }
}

// MARK: - Room

struct EnemySpawn: Sendable {
    let kind: EnemyKind
    let col: Int
    let row: Int
}

struct Room: Sendable {
    let id: Int
    /// `roomCols × roomRows` tiles, row-major. Index = `y * cols + x`.
    let tiles: [TileKind]
    /// Map of edge-direction → adjacent room id (for transition wiring).
    let neighbors: [Direction: Int]
    /// Initial enemy spawns in *tile* coordinates with their kind.
    let enemySpawns: [EnemySpawn]

    func tile(col: Int, row: Int) -> TileKind {
        guard (0..<QuestKidLayout.roomCols).contains(col),
              (0..<QuestKidLayout.roomRows).contains(row) else { return .tree }
        return tiles[row * QuestKidLayout.roomCols + col]
    }
}

// MARK: - World — 4 rooms in a 2×2 grid
//
//   [0 meadow ][1 grove ]
//   [2 clearing][3 sands ]
//
// Door legend in the string layouts:
//   "."  grass      "R"  rock wall (perimeter)
//   "T"  tree       "s"  sand
//   "K"  rock (interior boulder, walkable-around)
//   "D"  door — direction auto-resolved by the edge it's on
//
// Every row must be exactly `roomCols` chars (16). Each room must
// have exactly `roomRows` rows (8). The build() function precondition
// enforces both.

enum QuestKidWorld {
    static let rooms: [Room] = [
        room0_meadow,
        room1_grove,
        room2_clearing,
        room3_sands,
        room4_antechamber,
        room5_boss,
        room6_vault
    ]

    /// Starting room. Exits: right → 1, down → 2.
    static let room0_meadow = Room(
        id: 0,
        tiles: build(
            "RRRRRRRRRRRRRRRR",
            "R..............R",
            "R..T...........D",
            "R..............R",
            "R........T.....R",
            "R..............R",
            "R...T..........R",
            "RRRRRRRDRRRRRRRR"
        ),
        neighbors: [.right: 1, .down: 2],
        enemySpawns: [EnemySpawn(kind: .octorock, col: 8, row: 4)]
    )

    /// Northeast room. Exits: left → 0, down → 3.
    static let room1_grove = Room(
        id: 1,
        tiles: build(
            "RRRRRRRRRRRRRRRR",
            "R..............R",
            "D...T.....T....R",
            "R..............R",
            "R......T.......R",
            "R...T..........R",
            "R..........T...R",
            "RRRRRRRDRRRRRRRR"
        ),
        neighbors: [.left: 0, .down: 3],
        enemySpawns: [
            EnemySpawn(kind: .octorock, col: 11, row: 5),
            EnemySpawn(kind: .charger,  col: 6,  row: 3)
        ]
    )

    /// Southwest room. Exits: up → 0, right → 3.
    static let room2_clearing = Room(
        id: 2,
        tiles: build(
            "RRRRRRRDRRRRRRRR",
            "R........K.....R",
            "R..K...........D",
            "R..............R",
            "R........K.....R",
            "R..K...........R",
            "R..............R",
            "RRRRRRRRRRRRRRRR"
        ),
        neighbors: [.up: 0, .right: 3],
        enemySpawns: [EnemySpawn(kind: .shooter, col: 12, row: 5)]
    )

    /// Southeast room. Sand floor with scattered boulders.
    /// Exits: up → 1, left → 2, down → 4 (dungeon antechamber).
    static let room3_sands = Room(
        id: 3,
        tiles: build(
            "RRRRRRRDRRRRRRRR",
            "RssssssssssssssR",
            "DsssssKssssssssR",
            "RssssssssssssssR",
            "RssssssKsssssssR",
            "RsssKssssssssssR",
            "RssssssssssKsssR",
            "RRRRRRRDRRRRRRRR"
        ),
        neighbors: [.up: 1, .left: 2, .down: 4],
        enemySpawns: [
            EnemySpawn(kind: .shooter, col: 10, row: 3),
            EnemySpawn(kind: .charger, col: 5,  row: 5)
        ]
    )

    /// Dungeon Antechamber — guards on stone floor with two pillars
    /// (rocks) and a key entity (placed by state, not tiles) in the
    /// middle. Locked door at the bottom leads to the boss room.
    /// `S` on the left wall is a *secret passage* — looks like wallDark
    /// with a subtle crack, but is walkable and transitions to the vault.
    static let room4_antechamber = Room(
        id: 4,
        tiles: build(
            "WWWWWWWDWWWWWWWW",
            "WbbbbbbbbbbbbbbW",
            "SbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbKbbbbbbbbbbKbW",
            "WbbbbbbbbbbbbbbW",
            "WWWWWWWLWWWWWWWW"
        ),
        neighbors: [.up: 3, .down: 5, .left: 6],
        enemySpawns: [
            EnemySpawn(kind: .charger, col: 3, row: 5),
            EnemySpawn(kind: .charger, col: 12, row: 5)
        ]
    )

    /// Boss Room — wide stone arena with the boss in the upper half.
    /// The top door starts as a regular door (the lock side lives in
    /// the antechamber); after the boss dies, the state triggers the
    /// WIN screen.
    static let room5_boss = Room(
        id: 5,
        tiles: build(
            "WWWWWWWDWWWWWWWW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WWWWWWWWWWWWWWWW"
        ),
        neighbors: [.up: 4],
        enemySpawns: [EnemySpawn(kind: .boss, col: 7, row: 2)]
    )

    /// Secret Vault — accessed via a hidden passage on the left wall
    /// of the antechamber. Contains a persistent big-heart pickup
    /// (full HP restore). The exit `D` on the right wall returns the
    /// player to the antechamber.
    static let room6_vault = Room(
        id: 6,
        tiles: build(
            "WWWWWWWWWWWWWWWW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbD",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WbbbbbbbbbbbbbbW",
            "WWWWWWWWWWWWWWWW"
        ),
        neighbors: [.right: 4],
        enemySpawns: []
    )

    // MARK: - Tile builder

    /// Build a tile row from a string of characters. "D" is auto-classified
    /// by which edge it lands on (top → .up, bottom → .down, etc.).
    private static func build(_ rows: String...) -> [TileKind] {
        precondition(rows.count == QuestKidLayout.roomRows,
                     "Room must have \(QuestKidLayout.roomRows) rows; got \(rows.count)")
        var out: [TileKind] = []
        out.reserveCapacity(QuestKidLayout.roomCols * QuestKidLayout.roomRows)

        for (rowIdx, row) in rows.enumerated() {
            let chars = Array(row)
            precondition(chars.count == QuestKidLayout.roomCols,
                         "Room row \(rowIdx) must be \(QuestKidLayout.roomCols) cols; got \(chars.count) — '\(row)'")
            for (colIdx, ch) in chars.enumerated() {
                // "D", "L", "S" all auto-classify by edge position:
                //   D → .door  L → .lockedDoor  S → .secretPassage
                if ch == "D" || ch == "L" || ch == "S" {
                    let dir: Direction
                    if rowIdx == 0 { dir = .up }
                    else if rowIdx == QuestKidLayout.roomRows - 1 { dir = .down }
                    else if colIdx == 0 { dir = .left }
                    else if colIdx == QuestKidLayout.roomCols - 1 { dir = .right }
                    else { dir = .down }
                    switch ch {
                    case "L": out.append(.lockedDoor(dir))
                    case "S": out.append(.secretPassage(dir))
                    default:  out.append(.door(dir))
                    }
                    continue
                }
                switch ch {
                case ".": out.append(.grass)
                case "s": out.append(.sand)
                case "R": out.append(.rock)
                case "T": out.append(.tree)
                case "K": out.append(.rock)
                case "W": out.append(.wallDark)    // dungeon wall (was water)
                case "b": out.append(.stone)        // dungeon floor
                default:  out.append(.grass)
                }
            }
        }
        return out
    }
}
