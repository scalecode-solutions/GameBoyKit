import Foundation
import Observation

// MARK: - Entities

struct Player: Sendable {
    /// Pixel position of the player's *top-left* corner inside the
    /// room. The hitbox is 12×12 inset 2px on each side from the 16×16
    /// sprite cell.
    var x: Double = 128
    var y: Double = 64
    var facing: Direction = .down
    var hp: Int = 6        // half-hearts; 6 = three full hearts
    var maxHP: Int = 6
    /// Remaining invulnerability time after a hit (seconds). The
    /// sprite flickers while > 0.
    var iframes: Double = 0
    /// Remaining time in a sword swing animation/hitbox (seconds).
    var swordTimer: Double = 0
    /// Recently-applied knockback velocity (pixels/sec). Decays.
    var knockbackVX: Double = 0
    var knockbackVY: Double = 0
    /// True after the player has picked up the dungeon key. While
    /// true, all `.lockedDoor` tiles behave as passable doors.
    var hasKey: Bool = false

    static let size: Double = 16
    static let hitboxInset: Double = 2

    /// Player bounding box (pixel coords inside the room).
    var hitbox: BoundingBox {
        BoundingBox(
            x: x + Player.hitboxInset,
            y: y + Player.hitboxInset,
            w: Player.size - Player.hitboxInset * 2,
            h: Player.size - Player.hitboxInset * 2
        )
    }
}

struct Enemy: Sendable, Identifiable {
    let id: UUID
    var kind: EnemyKind
    var x: Double
    var y: Double
    var facing: Direction
    var hp: Int
    var aiTimer: Double = 0     // time until next AI decision
    var hitFlash: Double = 0    // remaining flash after sword hit
    var shotCooldown: Double = 0 // shooter only — time until next projectile
    var isCharging: Bool = false // charger only — committed to a charge?
    /// Boss only — what attack we've committed to but haven't executed
    /// yet. Combined with `telegraphTimer` gives the player a visible
    /// wind-up to read and dodge.
    var pendingAttack: BossAttack? = nil
    var telegraphTimer: Double = 0

    static let size: Double = 16

    /// Pixel dimension of this enemy's bounding cell. Bosses are 32px;
    /// every other enemy is 16px.
    var dimension: Double { kind == .boss ? 32 : 16 }

    var hitbox: BoundingBox {
        BoundingBox(x: x + 2, y: y + 2, w: dimension - 4, h: dimension - 4)
    }

    static func make(kind: EnemyKind, x: Double, y: Double) -> Enemy {
        switch kind {
        case .octorock:
            return Enemy(id: UUID(), kind: kind, x: x, y: y, facing: .down, hp: 2)
        case .shooter:
            return Enemy(id: UUID(), kind: kind, x: x, y: y, facing: .down, hp: 3,
                         shotCooldown: 1.5)
        case .charger:
            return Enemy(id: UUID(), kind: kind, x: x, y: y, facing: .down, hp: 2,
                         aiTimer: 0)
        case .boss:
            return Enemy(id: UUID(), kind: kind, x: x, y: y, facing: .down, hp: 8,
                         aiTimer: 1.4, shotCooldown: 2.0)
        }
    }
}

enum EnemyKind: Sendable, Hashable {
    case octorock   // wanders randomly
    case shooter    // stationary, fires rocks toward player
    case charger    // line-of-sight pursuit, runs straight at player
    case boss       // dungeon boss — 32×32 sprite, fan shot + charge, 8 HP
}

/// Boss attack types — tracked separately from execution so we can
/// render a "wind-up" telegraph before each.
enum BossAttack: Sendable, Hashable {
    case fanShot
    case charge
}

struct Projectile: Sendable, Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var ttl: Double = 4.0

    static let size: Double = 6

    var hitbox: BoundingBox {
        BoundingBox(x: x, y: y, w: Projectile.size, h: Projectile.size)
    }
}

enum HeartKind: Sendable, Hashable {
    /// Drops from enemies — restores ½ heart, despawns after a few seconds.
    case small
    /// Persistent (no TTL) reward heart — fully refills HP. Used for the
    /// hidden vault pickup.
    case big
}

struct HeartPickup: Sendable, Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    var ttl: Double = 9.0
    var bobPhase: Double = 0
    var kind: HeartKind = .small

    /// Big hearts (vault rewards) don't decay or flicker; small hearts do.
    var isPersistent: Bool { kind == .big }

    /// Visual footprint differs between small and big.
    var size: Double { kind == .big ? 14 : 10 }

    var hitbox: BoundingBox {
        BoundingBox(x: x, y: y, w: size, h: size)
    }
}

/// Persistent (no TTL) key pickup. Antechamber spawns one of these on
/// state init. Walking over it sets `player.hasKey = true` and unlocks
/// every `.lockedDoor` in the world.
struct KeyPickup: Sendable, Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    var bobPhase: Double = 0

    static let size: Double = 10

    var hitbox: BoundingBox {
        BoundingBox(x: x, y: y, w: KeyPickup.size, h: KeyPickup.size)
    }
}

struct BoundingBox: Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    func intersects(_ other: BoundingBox) -> Bool {
        x < other.x + other.w
            && x + w > other.x
            && y < other.y + other.h
            && y + h > other.y
    }
}

// MARK: - State

@MainActor
@Observable
final class QuestKidState {

    enum Phase: Equatable, Sendable {
        case title
        case playing
        case roomTransition(from: Int, to: Int, progress: Double, dir: Direction)
        case gameOver
        case won
    }

    // MARK: - Saved record

    /// Persistent record across cartridge launches.
    struct SaveRecord: Sendable, Equatable {
        var cleared: Bool = false
        /// Best player HP (in half-hearts) on completion. 0 = not cleared.
        var bestHearts: Int = 0
    }
    private(set) var record: SaveRecord

    // MARK: World

    private(set) var rooms: [Room] = QuestKidWorld.rooms
    private(set) var currentRoomIndex: Int = 0
    /// Per-room mutable state. Indexed by room id.
    private(set) var enemiesPerRoom: [[Enemy]]
    private(set) var projectilesPerRoom: [[Projectile]]
    private(set) var heartsPerRoom: [[HeartPickup]]
    private(set) var keysPerRoom: [[KeyPickup]]

    // MARK: Player

    private(set) var player: Player = Player()

    // MARK: Phase

    private(set) var phase: Phase = .title

    // MARK: Tuning

    static let playerSpeed: Double = 64            // pixels/sec
    static let swordDuration: Double = 0.18        // seconds
    static let iframeDuration: Double = 0.8        // post-hit invulnerability
    static let knockbackMagnitude: Double = 110    // pixels/sec
    static let knockbackDecay: Double = 6.0        // per-second exponential decay
    static let enemyWanderSpeed: Double = 28
    static let enemyDecisionInterval: Double = 1.4
    static let roomTransitionDuration: Double = 0.4
    // Phase 2 tuning
    static let chargerSpeed: Double = 58
    static let chargerSightRange: Double = 88
    static let shooterCooldown: Double = 2.4
    static let projectileSpeed: Double = 64
    static let heartDropChance: Double = 0.32
    // Phase 3 tuning
    static let bossSize: Double = 32
    static let bossPaceSpeed: Double = 18
    static let bossChargeSpeed: Double = 100
    static let bossFanCooldown: Double = 2.4    // doubled when enraged
    static let bossChargeCooldown: Double = 5.0
    static let bossEnrageHPThreshold: Int = 4    // 50% of 8
    // Phase 4 tuning
    static let bossFanWindUp: Double = 0.55     // wind-up before fan-shot
    static let bossChargeWindUp: Double = 0.45  // wind-up before charge

    /// Room ID where the dungeon key spawns.
    static let keyRoomID: Int = 4
    /// Room ID where the boss is fought.
    static let bossRoomID: Int = 5
    /// Room ID of the secret vault that holds the big heart.
    static let vaultRoomID: Int = 6

    // MARK: - Persistence

    private static let savedClearedKey = "gbk.questkid.cleared"
    private static let savedHeartsKey  = "gbk.questkid.bestHearts"

    private static func loadRecord() -> SaveRecord {
        let defaults = UserDefaults.standard
        return SaveRecord(
            cleared: defaults.bool(forKey: savedClearedKey),
            bestHearts: defaults.integer(forKey: savedHeartsKey)
        )
    }

    private func saveRecord() {
        let defaults = UserDefaults.standard
        defaults.set(record.cleared, forKey: Self.savedClearedKey)
        defaults.set(record.bestHearts, forKey: Self.savedHeartsKey)
    }

    init() {
        self.record = Self.loadRecord()
        // Hydrate per-room state from spawn templates.
        var enemies: [[Enemy]] = []
        for room in QuestKidWorld.rooms {
            let roomEnemies = room.enemySpawns.map { spawn in
                Enemy.make(
                    kind: spawn.kind,
                    x: Double(spawn.col * QuestKidLayout.tileSize),
                    y: Double(spawn.row * QuestKidLayout.tileSize)
                )
            }
            enemies.append(roomEnemies)
        }
        self.enemiesPerRoom = enemies
        self.projectilesPerRoom = Array(repeating: [], count: QuestKidWorld.rooms.count)
        // Hearts: a persistent big heart sits in the centre of the vault.
        var hearts: [[HeartPickup]] = Array(repeating: [], count: QuestKidWorld.rooms.count)
        hearts[Self.vaultRoomID] = [HeartPickup(
            id: UUID(),
            x: Double(7 * QuestKidLayout.tileSize) + 1,
            y: Double(3 * QuestKidLayout.tileSize) + 1,
            kind: .big
        )]
        self.heartsPerRoom = hearts
        // Place a key pickup in the antechamber, on the floor between
        // the two pillars (col 7, row 4 ≈ middle of the room).
        var keys: [[KeyPickup]] = Array(repeating: [], count: QuestKidWorld.rooms.count)
        keys[Self.keyRoomID] = [KeyPickup(
            id: UUID(),
            x: Double(7 * QuestKidLayout.tileSize) + 3,
            y: Double(3 * QuestKidLayout.tileSize) + 3
        )]
        self.keysPerRoom = keys
        // Place player roughly centered in the meadow.
        self.player.x = Double((QuestKidLayout.roomCols / 2 - 1) * QuestKidLayout.tileSize)
        self.player.y = Double((QuestKidLayout.roomRows / 2 - 1) * QuestKidLayout.tileSize)
    }

    var currentRoom: Room { rooms[currentRoomIndex] }
    var currentEnemies: [Enemy] {
        get { enemiesPerRoom[currentRoomIndex] }
        set { enemiesPerRoom[currentRoomIndex] = newValue }
    }
    var currentProjectiles: [Projectile] {
        get { projectilesPerRoom[currentRoomIndex] }
        set { projectilesPerRoom[currentRoomIndex] = newValue }
    }
    var currentHearts: [HeartPickup] {
        get { heartsPerRoom[currentRoomIndex] }
        set { heartsPerRoom[currentRoomIndex] = newValue }
    }
    var currentKeys: [KeyPickup] {
        get { keysPerRoom[currentRoomIndex] }
        set { keysPerRoom[currentRoomIndex] = newValue }
    }

    // MARK: - Tick

    /// Drive one frame of simulation. `dt` is elapsed seconds since the
    /// previous tick. `input` is the live D-pad direction (nil when not
    /// pressed) and a flag for the A button edge.
    /// Start (or restart) the game from the title screen.
    func start() {
        guard phase == .title else { return }
        phase = .playing
    }

    func tick(dt: Double, dpad: Direction?, swingPressed: Bool) {
        switch phase {
        case .title, .gameOver, .won:
            return
        case .roomTransition(let from, let to, let progress, let dir):
            let newProgress = progress + dt / Self.roomTransitionDuration
            if newProgress >= 1 {
                completeRoomTransition(to: to, dir: dir)
            } else {
                phase = .roomTransition(from: from, to: to, progress: newProgress, dir: dir)
            }
            return
        case .playing:
            break
        }

        // 1. Player input → intended velocity.
        var vx: Double = 0
        var vy: Double = 0
        if player.swordTimer <= 0, let d = dpad {
            // 4-way: priority to the strongest single axis. Our D-pad
            // can emit diagonals, but we lock movement to a single axis
            // for that classic Zelda feel.
            switch d {
            case .up:    vy = -1; player.facing = .up
            case .down:  vy =  1; player.facing = .down
            case .left:  vx = -1; player.facing = .left
            case .right: vx =  1; player.facing = .right
            }
        }

        // 2. Move player (with knockback, axis-separated collision).
        let moveX = vx * Self.playerSpeed * dt + player.knockbackVX * dt
        let moveY = vy * Self.playerSpeed * dt + player.knockbackVY * dt
        movePlayer(dx: moveX, dy: moveY)

        // 3. Decay knockback.
        let decay = exp(-Self.knockbackDecay * dt)
        player.knockbackVX *= decay
        player.knockbackVY *= decay
        if abs(player.knockbackVX) < 1 { player.knockbackVX = 0 }
        if abs(player.knockbackVY) < 1 { player.knockbackVY = 0 }

        // 4. Sword swing trigger.
        if swingPressed, player.swordTimer <= 0 {
            player.swordTimer = Self.swordDuration
        }
        if player.swordTimer > 0 {
            player.swordTimer = max(0, player.swordTimer - dt)
        }

        // 5. iframes decay.
        if player.iframes > 0 {
            player.iframes = max(0, player.iframes - dt)
        }

        // 6. Sword vs enemies (with potential heart drop on kill).
        if player.swordTimer > 0 {
            let hitbox = swordHitbox()
            var updated = currentEnemies
            var killedPositions: [(Double, Double)] = []
            for i in updated.indices {
                guard updated[i].hitFlash <= 0 else { continue }
                if hitbox.intersects(updated[i].hitbox) {
                    updated[i].hp -= 1
                    updated[i].hitFlash = 0.18
                    let pushDir = player.facing
                    let push: Double = 60
                    updated[i].x += pushDir.dx * push * dt
                    updated[i].y += pushDir.dy * push * dt
                    if updated[i].hp <= 0 {
                        killedPositions.append((updated[i].x, updated[i].y))
                    }
                }
            }
            // Check if a boss died before filtering, so we can trigger win.
            let bossDied = updated.contains { $0.kind == .boss && $0.hp <= 0 }
            currentEnemies = updated.filter { $0.hp > 0 }
            // Roll for heart drops at each kill site.
            var hearts = currentHearts
            for (x, y) in killedPositions where Double.random(in: 0..<1) < Self.heartDropChance {
                hearts.append(HeartPickup(id: UUID(), x: x + 3, y: y + 3))
            }
            currentHearts = hearts
            if bossDied {
                // Persist the win + best-hearts record.
                record.cleared = true
                record.bestHearts = max(record.bestHearts, player.hp)
                saveRecord()
                phase = .won
                return
            }
        }

        // 7. Enemy AI + movement + flash decay (per kind).
        var nextEnemies = currentEnemies
        var newProjectiles: [Projectile] = []
        for i in nextEnemies.indices {
            if nextEnemies[i].hitFlash > 0 {
                nextEnemies[i].hitFlash = max(0, nextEnemies[i].hitFlash - dt)
            }
            switch nextEnemies[i].kind {
            case .octorock:
                tickOctorock(at: i, in: &nextEnemies, dt: dt)
            case .charger:
                tickCharger(at: i, in: &nextEnemies, dt: dt)
            case .shooter:
                if let proj = tickShooter(at: i, in: &nextEnemies, dt: dt) {
                    newProjectiles.append(proj)
                }
            case .boss:
                let projs = tickBoss(at: i, in: &nextEnemies, dt: dt)
                newProjectiles.append(contentsOf: projs)
            }
        }
        currentEnemies = nextEnemies
        if !newProjectiles.isEmpty {
            currentProjectiles = currentProjectiles + newProjectiles
        }

        // 8. Projectile tick — move, age out, hit walls, hit player.
        tickProjectiles(dt: dt)

        // 9. Heart pickup tick — bob + ttl + collect on overlap.
        tickHeartPickups(dt: dt)

        // 9b. Key pickup tick — bob + collect on overlap.
        tickKeyPickups(dt: dt)

        // 10. Enemy vs player contact damage.
        if player.iframes <= 0 {
            for enemy in currentEnemies {
                if enemy.hitbox.intersects(player.hitbox) {
                    damagePlayer(from: enemy.x + Enemy.size / 2,
                                 fromY: enemy.y + Enemy.size / 2)
                    break
                }
            }
        }

        // 11. Death check.
        if player.hp <= 0 {
            phase = .gameOver
            return
        }

        // 12. Room transition check (player walked onto a door tile).
        checkRoomExit()
    }

    // MARK: - Per-kind AI

    private func tickOctorock(at i: Int, in enemies: inout [Enemy], dt: Double) {
        enemies[i].aiTimer -= dt
        if enemies[i].aiTimer <= 0 {
            enemies[i].aiTimer = Self.enemyDecisionInterval
            enemies[i].facing = Direction.allCases.randomElement()!
        }
        let dx = enemies[i].facing.dx * Self.enemyWanderSpeed * dt
        let dy = enemies[i].facing.dy * Self.enemyWanderSpeed * dt
        moveEnemy(at: i, in: &enemies, dx: dx, dy: dy)
    }

    private func tickCharger(at i: Int, in enemies: inout [Enemy], dt: Double) {
        let ex = enemies[i].x + Enemy.size / 2
        let ey = enemies[i].y + Enemy.size / 2
        let px = player.x + Player.size / 2
        let py = player.y + Player.size / 2
        let dxN = px - ex
        let dyN = py - ey
        let dist = (dxN * dxN + dyN * dyN).squareRoot()

        if enemies[i].isCharging {
            // Move in the committed facing direction; stop charging if we
            // hit a wall (handled in moveEnemy via random re-facing).
            let dx = enemies[i].facing.dx * Self.chargerSpeed * dt
            let dy = enemies[i].facing.dy * Self.chargerSpeed * dt
            let prevX = enemies[i].x
            let prevY = enemies[i].y
            moveEnemy(at: i, in: &enemies, dx: dx, dy: dy)
            if abs(enemies[i].x - prevX) < 0.5 && abs(enemies[i].y - prevY) < 0.5 {
                // Hit a wall, drop charge state.
                enemies[i].isCharging = false
                enemies[i].aiTimer = 0.8
            }
        } else {
            enemies[i].aiTimer -= dt
            if dist < Self.chargerSightRange, enemies[i].aiTimer <= 0 {
                // Commit to a charge in whichever axis is dominant.
                enemies[i].isCharging = true
                if abs(dxN) > abs(dyN) {
                    enemies[i].facing = dxN >= 0 ? .right : .left
                } else {
                    enemies[i].facing = dyN >= 0 ? .down : .up
                }
            } else if enemies[i].aiTimer <= 0 {
                // Idle wander while waiting for player.
                enemies[i].aiTimer = Self.enemyDecisionInterval
                enemies[i].facing = Direction.allCases.randomElement()!
                let dx = enemies[i].facing.dx * (Self.enemyWanderSpeed * 0.7) * dt
                let dy = enemies[i].facing.dy * (Self.enemyWanderSpeed * 0.7) * dt
                moveEnemy(at: i, in: &enemies, dx: dx, dy: dy)
            }
        }
    }

    /// The dungeon boss. Alternates between fan-shot (3 rocks fanning
    /// toward player) and a straight-line charge. Both intervals shrink
    /// when HP is at or below `bossEnrageHPThreshold`.
    ///
    /// Returns any projectiles fired this tick (collected by the main
    /// loop to add to the room's projectile list).
    private func tickBoss(at i: Int, in enemies: inout [Enemy], dt: Double) -> [Projectile] {
        let enraged = enemies[i].hp <= Self.bossEnrageHPThreshold
        let mul: Double = enraged ? 0.55 : 1.0
        let bossDim = Self.bossSize

        // Always face the player so the sprite reads alive.
        let ex = enemies[i].x + bossDim / 2
        let ey = enemies[i].y + bossDim / 2
        let px = player.x + Player.size / 2
        let py = player.y + Player.size / 2
        let dxN = px - ex
        let dyN = py - ey
        if abs(dxN) > abs(dyN) {
            enemies[i].facing = dxN >= 0 ? .right : .left
        } else {
            enemies[i].facing = dyN >= 0 ? .down : .up
        }

        // Telegraphing an attack? Don't act until wind-up completes.
        if enemies[i].telegraphTimer > 0 {
            enemies[i].telegraphTimer = max(0, enemies[i].telegraphTimer - dt)
            if enemies[i].telegraphTimer > 0 {
                return []   // still winding up
            }
            // Wind-up just completed — execute the queued attack.
            guard let attack = enemies[i].pendingAttack else { return [] }
            enemies[i].pendingAttack = nil
            switch attack {
            case .fanShot:
                enemies[i].shotCooldown = Self.bossFanCooldown * mul
                return makeFanShot(originX: ex, originY: ey,
                                   aimX: px, aimY: py)
            case .charge:
                enemies[i].isCharging = true
                if abs(dxN) > abs(dyN) {
                    enemies[i].facing = dxN >= 0 ? .right : .left
                } else {
                    enemies[i].facing = dyN >= 0 ? .down : .up
                }
                enemies[i].aiTimer = 1.4
                return []
            }
        }

        // Charging? Move and check for end.
        if enemies[i].isCharging {
            let prevX = enemies[i].x
            let prevY = enemies[i].y
            let dx = enemies[i].facing.dx * Self.bossChargeSpeed * dt
            let dy = enemies[i].facing.dy * Self.bossChargeSpeed * dt
            moveBoss(at: i, in: &enemies, dx: dx, dy: dy)
            enemies[i].aiTimer -= dt
            let movedLittle = abs(enemies[i].x - prevX) < 0.5
                && abs(enemies[i].y - prevY) < 0.5
            if enemies[i].aiTimer <= 0 || movedLittle {
                enemies[i].isCharging = false
                enemies[i].aiTimer = Self.bossChargeCooldown * mul
            }
            return []
        }

        // Cooldowns
        enemies[i].aiTimer -= dt
        enemies[i].shotCooldown -= dt

        // Decide what to telegraph next.
        if enemies[i].shotCooldown <= 0 {
            enemies[i].pendingAttack = .fanShot
            enemies[i].telegraphTimer = Self.bossFanWindUp
            return []
        }
        if enemies[i].aiTimer <= 0 {
            enemies[i].pendingAttack = .charge
            enemies[i].telegraphTimer = Self.bossChargeWindUp
            return []
        }

        // Slow pace in the current facing while idle.
        let dx = enemies[i].facing.dx * Self.bossPaceSpeed * dt
        let dy = enemies[i].facing.dy * Self.bossPaceSpeed * dt
        moveBoss(at: i, in: &enemies, dx: dx, dy: dy)
        return []
    }

    /// 3-rock fan toward the player. The middle rock aims directly;
    /// the flanking rocks spread out by ±25°.
    private func makeFanShot(originX: Double, originY: Double,
                             aimX: Double,    aimY: Double) -> [Projectile] {
        let dx = aimX - originX
        let dy = aimY - originY
        let mag = max(1, (dx * dx + dy * dy).squareRoot())
        let nx = dx / mag
        let ny = dy / mag
        let speed = Self.projectileSpeed
        let spread = 25.0 * .pi / 180.0
        func rotated(_ angle: Double) -> (Double, Double) {
            let cosA = cos(angle), sinA = sin(angle)
            let rx = nx * cosA - ny * sinA
            let ry = nx * sinA + ny * cosA
            return (rx * speed, ry * speed)
        }
        let (vx0, vy0) = rotated(-spread)
        let (vx1, vy1) = rotated(0)
        let (vx2, vy2) = rotated(spread)
        let startX = originX - Projectile.size / 2
        let startY = originY - Projectile.size / 2
        return [
            Projectile(id: UUID(), x: startX, y: startY, vx: vx0, vy: vy0),
            Projectile(id: UUID(), x: startX, y: startY, vx: vx1, vy: vy1),
            Projectile(id: UUID(), x: startX, y: startY, vx: vx2, vy: vy2)
        ]
    }

    /// Boss-specific move (uses 32×32 hitbox vs 16×16 for other enemies).
    private func moveBoss(at i: Int, in enemies: inout [Enemy], dx: Double, dy: Double) {
        let e = enemies[i]
        let d = Enemy.size * 2     // 32
        let tryX = BoundingBox(x: e.x + 2 + dx, y: e.y + 2,
                               w: d - 4, h: d - 4)
        if !collidesWithSolids(tryX) {
            enemies[i].x += dx
        }
        let tryY = BoundingBox(x: enemies[i].x + 2, y: e.y + 2 + dy,
                               w: d - 4, h: d - 4)
        if !collidesWithSolids(tryY) {
            enemies[i].y += dy
        }
        // Clamp inside play area.
        let maxX = Double(QuestKidLayout.playWidth)  - d
        let maxY = Double(QuestKidLayout.playHeight) - d
        enemies[i].x = min(max(enemies[i].x, 0), maxX)
        enemies[i].y = min(max(enemies[i].y, 0), maxY)
    }

    private func tickShooter(at i: Int, in enemies: inout [Enemy], dt: Double) -> Projectile? {
        // Shooters don't move. They just cycle the cooldown and fire at
        // the player when it's up.
        enemies[i].shotCooldown -= dt
        // Always face the player so the sprite looks alive.
        let ex = enemies[i].x + Enemy.size / 2
        let ey = enemies[i].y + Enemy.size / 2
        let px = player.x + Player.size / 2
        let py = player.y + Player.size / 2
        let dxN = px - ex
        let dyN = py - ey
        if abs(dxN) > abs(dyN) {
            enemies[i].facing = dxN >= 0 ? .right : .left
        } else {
            enemies[i].facing = dyN >= 0 ? .down : .up
        }
        guard enemies[i].shotCooldown <= 0 else { return nil }
        enemies[i].shotCooldown = Self.shooterCooldown

        // Fire a projectile toward the player along the shooter's facing.
        let mag = max(1, (dxN * dxN + dyN * dyN).squareRoot())
        let vx = (dxN / mag) * Self.projectileSpeed
        let vy = (dyN / mag) * Self.projectileSpeed
        let startX = ex - Projectile.size / 2
        let startY = ey - Projectile.size / 2
        return Projectile(id: UUID(), x: startX, y: startY, vx: vx, vy: vy)
    }

    // MARK: - Projectiles + pickups

    private func tickProjectiles(dt: Double) {
        var projs = currentProjectiles
        for i in projs.indices.reversed() {
            projs[i].x += projs[i].vx * dt
            projs[i].y += projs[i].vy * dt
            projs[i].ttl -= dt
            let box = projs[i].hitbox
            // Hit player?
            if player.iframes <= 0, box.intersects(player.hitbox) {
                damagePlayer(from: projs[i].x + Projectile.size / 2,
                             fromY: projs[i].y + Projectile.size / 2)
                projs.remove(at: i)
                continue
            }
            // Out of bounds or expired?
            if projs[i].ttl <= 0
                || projs[i].x < 0 || projs[i].x > Double(QuestKidLayout.playWidth)
                || projs[i].y < 0 || projs[i].y > Double(QuestKidLayout.playHeight) {
                projs.remove(at: i)
                continue
            }
            // Tile collision?
            if collidesWithSolids(box) {
                projs.remove(at: i)
                continue
            }
        }
        currentProjectiles = projs
    }

    private func tickKeyPickups(dt: Double) {
        var keys = currentKeys
        for i in keys.indices.reversed() {
            keys[i].bobPhase += dt
            if keys[i].hitbox.intersects(player.hitbox) {
                player.hasKey = true
                keys.remove(at: i)
            }
        }
        currentKeys = keys
    }

    private func tickHeartPickups(dt: Double) {
        var hearts = currentHearts
        for i in hearts.indices.reversed() {
            hearts[i].bobPhase += dt
            // Small drops decay; big rewards don't.
            if !hearts[i].isPersistent {
                hearts[i].ttl -= dt
                if hearts[i].ttl <= 0 {
                    hearts.remove(at: i)
                    continue
                }
            }
            if hearts[i].hitbox.intersects(player.hitbox) {
                switch hearts[i].kind {
                case .small:
                    // Don't waste a small drop at full HP.
                    if player.hp < player.maxHP {
                        player.hp = min(player.maxHP, player.hp + 1)
                        hearts.remove(at: i)
                    }
                case .big:
                    // Always collect — full refill, persistent reward.
                    player.hp = player.maxHP
                    hearts.remove(at: i)
                }
            }
        }
        currentHearts = hearts
    }

    private func damagePlayer(from sourceX: Double, fromY sourceY: Double) {
        player.hp = max(0, player.hp - 1)
        player.iframes = Self.iframeDuration
        let cx = player.x + Player.size / 2
        let cy = player.y + Player.size / 2
        let dxN = cx - sourceX
        let dyN = cy - sourceY
        let mag = max(0.001, (dxN * dxN + dyN * dyN).squareRoot())
        player.knockbackVX = (dxN / mag) * Self.knockbackMagnitude
        player.knockbackVY = (dyN / mag) * Self.knockbackMagnitude
    }

    // MARK: - Sword hitbox

    private func swordHitbox() -> BoundingBox {
        let length: Double = 14
        let thickness: Double = 8
        let px = player.x
        let py = player.y
        switch player.facing {
        case .up:    return BoundingBox(x: px + (Player.size - thickness) / 2, y: py - length, w: thickness, h: length)
        case .down:  return BoundingBox(x: px + (Player.size - thickness) / 2, y: py + Player.size, w: thickness, h: length)
        case .left:  return BoundingBox(x: px - length, y: py + (Player.size - thickness) / 2, w: length, h: thickness)
        case .right: return BoundingBox(x: px + Player.size, y: py + (Player.size - thickness) / 2, w: length, h: thickness)
        }
    }

    // MARK: - Movement helpers

    private func movePlayer(dx: Double, dy: Double) {
        // Axis-separated collision against tile grid.
        let tryX = player.x + dx
        let candidate = BoundingBox(
            x: tryX + Player.hitboxInset,
            y: player.y + Player.hitboxInset,
            w: Player.size - Player.hitboxInset * 2,
            h: Player.size - Player.hitboxInset * 2
        )
        if !collidesWithSolids(candidate) {
            player.x = tryX
        } else {
            // Stop knockback on collision so player doesn't get pinned.
            player.knockbackVX = 0
        }

        let tryY = player.y + dy
        let candidateY = BoundingBox(
            x: player.x + Player.hitboxInset,
            y: tryY + Player.hitboxInset,
            w: Player.size - Player.hitboxInset * 2,
            h: Player.size - Player.hitboxInset * 2
        )
        if !collidesWithSolids(candidateY) {
            player.y = tryY
        } else {
            player.knockbackVY = 0
        }

        // Clamp to room bounds (so we don't fall off when not at a door).
        let maxX = Double(QuestKidLayout.playWidth)  - Player.size
        let maxY = Double(QuestKidLayout.playHeight) - Player.size
        player.x = min(max(player.x, 0), maxX)
        player.y = min(max(player.y, 0), maxY)
    }

    private func moveEnemy(at index: Int, in enemies: inout [Enemy], dx: Double, dy: Double) {
        let e = enemies[index]
        // X axis
        let tryBoxX = BoundingBox(x: e.x + 2 + dx, y: e.y + 2, w: Enemy.size - 4, h: Enemy.size - 4)
        if !collidesWithSolids(tryBoxX) {
            enemies[index].x += dx
        } else {
            enemies[index].facing = Direction.allCases.randomElement() ?? .down
        }
        // Y axis
        let tryBoxY = BoundingBox(x: enemies[index].x + 2, y: e.y + 2 + dy, w: Enemy.size - 4, h: Enemy.size - 4)
        if !collidesWithSolids(tryBoxY) {
            enemies[index].y += dy
        } else {
            enemies[index].facing = Direction.allCases.randomElement() ?? .down
        }
        // Clamp
        let maxX = Double(QuestKidLayout.playWidth)  - Enemy.size
        let maxY = Double(QuestKidLayout.playHeight) - Enemy.size
        enemies[index].x = min(max(enemies[index].x, 0), maxX)
        enemies[index].y = min(max(enemies[index].y, 0), maxY)
    }

    private func collidesWithSolids(_ box: BoundingBox) -> Bool {
        // Check the up-to-4 tiles the box overlaps.
        let minCol = Int(floor(box.x / Double(QuestKidLayout.tileSize)))
        let maxCol = Int(floor((box.x + box.w - 0.001) / Double(QuestKidLayout.tileSize)))
        let minRow = Int(floor(box.y / Double(QuestKidLayout.tileSize)))
        let maxRow = Int(floor((box.y + box.h - 0.001) / Double(QuestKidLayout.tileSize)))
        for r in minRow...maxRow {
            for c in minCol...maxCol {
                if isSolidForPlayer(currentRoom.tile(col: c, row: r)) { return true }
            }
        }
        return false
    }

    /// Locked doors are normally solid, but become passable once the
    /// player has the key.
    private func isSolidForPlayer(_ tile: TileKind) -> Bool {
        if case .lockedDoor = tile, player.hasKey { return false }
        return tile.isSolid
    }

    // MARK: - Room transitions

    private func checkRoomExit() {
        let tileSize = Double(QuestKidLayout.tileSize)
        let cx = player.x + Player.size / 2
        let cy = player.y + Player.size / 2
        let col = Int(cx / tileSize)
        let row = Int(cy / tileSize)
        guard (0..<QuestKidLayout.roomCols).contains(col),
              (0..<QuestKidLayout.roomRows).contains(row) else { return }
        let tile = currentRoom.tile(col: col, row: row)
        // Regular door
        if case .door(let dir) = tile,
           let neighborID = currentRoom.neighbors[dir] {
            phase = .roomTransition(
                from: currentRoomIndex,
                to: neighborID,
                progress: 0,
                dir: dir
            )
            return
        }
        // Locked door — only passable if player has the key
        if case .lockedDoor(let dir) = tile,
           player.hasKey,
           let neighborID = currentRoom.neighbors[dir] {
            phase = .roomTransition(
                from: currentRoomIndex,
                to: neighborID,
                progress: 0,
                dir: dir
            )
            return
        }
        // Secret passage — works like a regular door but is visually
        // disguised as a wall (the visual cue is just a subtle crack).
        if case .secretPassage(let dir) = tile,
           let neighborID = currentRoom.neighbors[dir] {
            phase = .roomTransition(
                from: currentRoomIndex,
                to: neighborID,
                progress: 0,
                dir: dir
            )
        }
    }

    private func completeRoomTransition(to roomID: Int, dir: Direction) {
        currentRoomIndex = roomID
        // Place player at the opposite-edge entrance.
        let tileSize = Double(QuestKidLayout.tileSize)
        let playW = Double(QuestKidLayout.playWidth)
        let playH = Double(QuestKidLayout.playHeight)
        switch dir {
        case .up:    player.y = playH - Player.size - tileSize       // enter from bottom
        case .down:  player.y = tileSize                              // enter from top
        case .left:  player.x = playW - Player.size - tileSize       // enter from right
        case .right: player.x = tileSize                              // enter from left
        }
        // Clear knockback so player doesn't get pushed back into the door.
        player.knockbackVX = 0
        player.knockbackVY = 0
        phase = .playing
    }

    // MARK: - Lifecycle

    func reset() {
        var enemies: [[Enemy]] = []
        for room in QuestKidWorld.rooms {
            let roomEnemies = room.enemySpawns.map { spawn in
                Enemy.make(
                    kind: spawn.kind,
                    x: Double(spawn.col * QuestKidLayout.tileSize),
                    y: Double(spawn.row * QuestKidLayout.tileSize)
                )
            }
            enemies.append(roomEnemies)
        }
        enemiesPerRoom = enemies
        projectilesPerRoom = Array(repeating: [], count: QuestKidWorld.rooms.count)
        var hearts: [[HeartPickup]] = Array(repeating: [], count: QuestKidWorld.rooms.count)
        hearts[Self.vaultRoomID] = [HeartPickup(
            id: UUID(),
            x: Double(7 * QuestKidLayout.tileSize) + 1,
            y: Double(3 * QuestKidLayout.tileSize) + 1,
            kind: .big
        )]
        heartsPerRoom = hearts
        var keys: [[KeyPickup]] = Array(repeating: [], count: QuestKidWorld.rooms.count)
        keys[Self.keyRoomID] = [KeyPickup(
            id: UUID(),
            x: Double(7 * QuestKidLayout.tileSize) + 3,
            y: Double(3 * QuestKidLayout.tileSize) + 3
        )]
        keysPerRoom = keys
        currentRoomIndex = 0
        player = Player()
        player.x = Double((QuestKidLayout.roomCols / 2 - 1) * QuestKidLayout.tileSize)
        player.y = Double((QuestKidLayout.roomRows / 2 - 1) * QuestKidLayout.tileSize)
        phase = .playing    // skip the title on retry — straight to play
    }
}
