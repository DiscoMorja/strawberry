# Strawberry — Game Design Document (v0.2, working draft)

> Working title. Godot 4.7, 2D top-down. This doc is the source of truth for design intent;
> the build order lives in [PROTOTYPE_PLAN.md](PROTOTYPE_PLAN.md).

---

## 1. Elevator pitch

A 2D top-down action roguelike where you lead a small party through ever-deeper dungeon biomes,
fighting hordes with weighty, Vermintide-style melee. Everything you bring back — followers, gear,
skillbooks — builds up an ancient castle that you must periodically defend against massive sieges.

**One line:** *Vermintide's melee and horde pressure, Dungeon Siege's party, Hades' run-and-return loop, with a castle you defend.*

## 2. Design pillars

Every feature should serve at least one pillar. If it serves none, cut it.

1. **Weighty, readable melee.** Every swing commits. Cleave, stagger, block and dodge are the
   vocabulary; reading telegraphs is the skill.
2. **Triage under pressure.** Hordes are the noise, specials are the signal. The core decision
   every few seconds is *"what do I kill first?"*
3. **Your party is your build.** Power comes mostly from *who* you bring and how they're equipped,
   not just numbers on the hero.
4. **The castle remembers.** Each run leaves a permanent mark — a repaired wall, a new recruit,
   a book on the shelf — and the castle gets tested by it.

## 3. Core loops

### 3.1 Moment-to-moment (seconds)
Move → read threats → pick target → attack / block / dodge / push → manage stamina → swap or command party.

### 3.2 Run loop (20–40 min)
Choose loadout at castle → enter biome → clear room chain (combat, loot, events, recruits) →
biome boss → continue deeper **or** extract → return to castle (on death or extraction).

### 3.3 Meta loop (hours)
Spend loot on castle repairs → unlock castle functions → manage roster and stash →
**siege** arrives on the threat clock → defend with everything you have → dungeon difficulty rises → repeat.

```
 ┌──────────── CASTLE ────────────┐
 │ repair · stash · roster · train │◄──────────────┐
 └──────┬─────────────────▲────────┘               │
        │ loadout         │ siege (every N runs)   │ extract / die
        ▼                 │                        │
   ┌─────────┐   ┌────────┴──┐   ┌─────────┐   ┌───┴────┐
   │ Biome 1 ├──►│  Boss 1   ├──►│ Biome 2 ├──►│ ...    │
   └─────────┘   └───────────┘   └─────────┘   └────────┘
```

## 4. Narrative frame

- **Run 0 (tutorial):** Alone in a dark dungeon. Teaches movement, light/heavy attack, block, dodge.
  First follower is found mid-dungeon (teaches party). Ends at the first boss — win or die,
  you awaken at the castle.
- **Prologue siege (scripted):** The castle is overrun; the player fights with whatever they found.
  This is a *tutorial for siege defense* that is designed to be lost. At the breaking point the
  **Wizard** wipes the field with a shockwave, introduces himself, warns of the next attack,
  and leaves for "the next castle".
- **Ongoing mystery hooks:** Who used this castle before? How many castles are there? Why do the
  sieges come? Drip-feed lore through repaired rooms, skillbooks, and boss drops.
- **Tone:** Grim, worn fantasy with warmth from party banter. The castle is the one lit place.

> Open: does the Wizard return (e.g. as a reward for surviving X sieges, or as an endgame twist)?

## 5. Combat system

Inspired by Vermintide, adapted to top-down. **The top-down translation is the biggest design risk** —
Vermintide's feel comes from first-person aim and sound cues. We compensate with strong
visual telegraphs, hit-stop, screen shake and directional indicators.

### 5.1 Player actions

| Action | Input (KB+M / Pad) | Notes |
|---|---|---|
| Move | WASD / LS | Facing follows aim, not movement. |
| Aim | Mouse / RS | Attacks go toward aim. |
| Light attack | LMB / RT | Weapon-defined chain (e.g. L1→L2→L3). Fast, low stagger. |
| Heavy attack | Hold LMB / Hold RT | Charge; high stagger, high cleave. |
| Block | RMB / LT | Frontal arc. Costs stamina per hit absorbed. |
| Push | Block + LMB | Short arc shove; staggers trash, costs stamina, interrupts. |
| Dodge | Space / B | Short dash. **Not** full i-frames — dodging *out of* an attack's arc is what saves you (Vermintide-style). Small i-frame window optional for tuning. |
| Skill 1–2 | Q / E | From skillbooks; cooldown-based. |
| Swap character | Tab / LB | Take direct control of another party member. |
| Party command | 1–4 / D-pad | Stance & orders (see §6). |

### 5.2 Core stats & rules

- **Stamina (shields):** Discrete pips. Blocking and pushing consume pips; regenerate when not blocking.
  Out of stamina → **guard break** (staggered). Encourages dodge/positioning over turtling.
- **Cleave (mass budget):** Each attack has a cleave value; each enemy has a mass. A swing keeps
  hitting enemies along its arc until cleave is spent. Hordes = low mass, elites = high mass.
  Damage falls off per target after the first.
- **Stagger:** Attacks deal stagger; enemies have stagger thresholds and tiers
  (flinch → stagger → knockdown). Staggered enemies take bonus damage and stop attacking.
  Stagger is how you control space; damage is how you clear it.
- **Headshot analogue — "Weak point / crit window":** Since there's no head aim, use timing:
  hitting an enemy during its *attack wind-up* (or from behind) counts as a critical/“exposed” hit.
- **Hit-stop & feedback:** Every hit freezes 30–80 ms scaled by weight. Mandatory, not polish.
- **Friendly fire:** Off for melee in v1; consider on for some skills (bombs, fire).

### 5.3 Weapons (archetypes, not a final list)

| Archetype | Cleave | Stagger | Speed | Role |
|---|---|---|---|---|
| Sword & shield | Med | Med | Med | All-rounder, best block |
| Greatsword / Axe | High | High | Slow | Horde clear |
| Dual daggers | Low | Low | Fast | Specials/elite killer, high crit |
| Spear | Low (pierce line) | Med | Med | Reach, priority picks |
| Bow / Crossbow | Pierce | Low | — | Ranged priority sniping, ammo-limited |
| Staff | Varies | Varies | — | Magic via skillbooks, overheat/mana |

Each weapon is a data resource: attack chain, per-attack wind-up/active/recovery, cleave, stagger, damage, arc.

## 6. Party system (Dungeon Siege inspired)

- **Party size:** Hero + up to 3 followers in a run (tune; maybe 2 early, grows with castle upgrades).
- **Direct control:** You control exactly one character at a time with full action combat.
  `Tab` swaps control; the previous character returns to AI. *This is how "control separately" works* —
  no RTS box-select micro in v1.
- **Orders (global or per-character):**
  - **Follow** (default) — stay near controlled character.
  - **Hold** — stay at a point.
  - **Focus** — attack the target under the cursor (key for priority targeting).
  - **Regroup** — drop everything, return to controlled character.
- **Stances (per follower, set in menu):** Aggressive / Defensive / Support. Defines target
  selection and engagement range.
- **AI targeting priority:** Followers should *partially* help with triage (e.g. archers prefer
  specials) but never solve it fully — the player's Focus order must matter.
- **Downed state:** Characters at 0 HP go *downed* (bleed-out timer), revivable by allies.
  Die when timer expires.
- **Followers have:** class/archetype, 1–2 traits (e.g. "Stubborn: +stagger resist", "Coward: flees at low HP"),
  equipment slots, skill slots, level.

### 6.1 The hero

The hero is a **fixed character** — always in the party, always the story's anchor.
If the hero dies, the run ends (see §10.1). Followers are the expendable, emotionally loaded layer.

### 6.2 Follower permadeath — "XCOM attachment"

Followers die permanently. Goal: **losing one stings but doesn't wreck you; keeping one alive for a
long time feels special.** The emotional value must come from *history*, not from raw power that
makes a death unrecoverable.

**Make survival special:**
- **Veterancy ranks** (Recruit → Veteran → Elite → Legend) earned by *runs survived*, not just XP.
  Each rank grants a small perk choice and a visual mark (cape, scar, banner color).
- **Name, nickname, and a service record:** runs survived, kills, specials killed, bosses slain,
  times revived. Nicknames are earned from deeds ("Bonebreaker" after 500 skeletons).
- **Bonds:** followers who survive runs together gain bond levels → small synergy perks when fighting
  near each other (e.g. auto-revive priority, shared stagger). Losing one hurts the other ("Grieving" trait, temporary).
- **Signature moments:** at Legend rank a follower unlocks a unique trait or personal skill.

**Make death not too punishing:**
- **Power curve is flat-ish:** a Legend is maybe ~30–40% stronger than a fresh recruit of the same class,
  not 3×. Most power lives in gear and skillbooks, which are recoverable.
- **Steady recruit supply:** Barracks always offers a few replacement recruits; good gear makes them viable fast.
- **Gear isn't lost with the follower** if the party extracts — the hero picks up the fallen's kit
  (lost only if the whole run fails).
- **Warning signs before death:** downed → bleed-out → dead, with loud UI/audio. Death should feel like
  *a mistake you saw coming*, not a random spike. Attack tokens (§7.2) prevent burst deaths.
- **Lingering wounds (optional):** on revive, a follower may gain an injury that requires sitting out
  the next run — an XCOM-style middle ground between "fine" and "dead".
- **Legacy:** fallen followers go on a **Memorial Wall** in the castle. Each memorial gives a tiny
  permanent bonus or passes a trait/skill fragment to a successor ("trained by Hilde").

**Hardcore tuning watch-list:** this is a deliberate risk. Track during playtests: how often
followers die, whether players feel it was fair, and whether players stop bringing their favorites
(a sign it's too punishing). Easy dials: bleed-out duration, revive speed, number of Rest rooms.

## 7. Enemies

Hordes are noise; specials are signal. Composition is driven by a **Director** (§8).

### 7.1 Roles

| Role | Example | Threat | Answer |
|---|---|---|---|
| **Trash (horde)** | Rats, ghouls, skeletons | Swarm, chip damage | Cleave, push |
| **Shielded** | Shield skeleton | Blocks frontal attacks | Heavy/stagger, flank |
| **Elite (armored)** | Knight, ogre | High HP & damage, telegraphed | Dodge, focus, crit window |
| **Disabler** ⚠ | Hooker / net-thrower | Grabs and drags a party member away | Kill on sight |
| **Ranged** ⚠ | Archer / caster | Pressure from range, blocks dodges | Close distance, ranged follower |
| **Assassin** ⚠ | Shadow pouncer | Pins a character, high burst | Push off, kill fast |
| **Bomber** ⚠ | Plague bloat | Area denial, kills grouped parties | Kill at range, spread out |
| **Summoner/Buffer** ⚠ | Necromancer, war-drummer | Multiplies or empowers horde | Priority kill |

⚠ = **priority target**. Specials get a distinct **audio cue + edge-of-screen indicator** on spawn.

### 7.2 Enemy design rules
- Every attack has a readable wind-up (color flash + shape telegraph on the ground).
- Max 1–2 simultaneous elite attacks hit the same character (attack token system — prevents unfair damage stacking).
- Per-biome families: each biome swaps visuals and adds 1–2 new roles or modifiers.

## 8. Director & difficulty

- **AI Director** (Left 4 Dead / Vermintide): tracks party intensity (damage taken, enemies nearby) and
  schedules **build-up → peak (horde) → relax** cycles. Specials spawn on a separate timer with caps per type.
- **Difficulty axes:**
  - **Depth** (biome/room in this run).
  - **Threat level** (global, increases per run / per siege). Raises enemy stats, special frequency,
    adds elite modifiers.
- "Scales over time" = threat level. Make it visible on the castle map (e.g. corruption meter).

## 9. Run structure (dungeon)

- **Biome = chain of rooms** with branching choice (2–3 exits showing room type icons).
  Rooms are **handmade chunks assembled procedurally** — far cheaper to make good than full procgen.
- **Room types:** Combat, Elite combat, Treasure, Recruit (follower event), Library (skillbook),
  Shrine (risk/reward buff), Rest (heal/revive), Boss.
- **Biome length:** ~8–12 rooms + boss.
- **Biome order (draft):** Crypts → Fungal Caverns → Drowned Halls → Ember Forge → Abyss. Each has a milestone boss.
- **Extraction:** After each boss, choose **descend** (keep going, higher reward) or **extract** (bank everything).

## 10. Loot & progression

- **Equipment:** Weapon, offhand, armor, trinket. Rarity tiers with rolled affixes
  (keep affix pool small and impactful: "+cleave", "push costs no stamina", "crit on staggered").
- **Skillbooks:** Teach an active skill to any character whose class permits it. Limited skill slots → choices.
- **Followers:** Recruited from events, rescued prisoners, or bought at castle later.
- **Character level:** Light per-character leveling; most power comes from gear and skills.
### 10.1 Death penalty — hardcore (decided)

- **Loot is unbanked until extraction.** Extraction happens after a boss (descend or extract) and
  possibly at rare mid-biome waystones.
- **Hero dies → run ends:** all *unbanked* loot is lost, and the gear of followers who died this run is lost.
  Surviving followers return to the castle (wounded) with the gear they're wearing.
- **Gear you brought in is at risk only on the characters who die** — the hero's starting loadout
  returns with them (fixed hero must stay playable).
- **Followers who die are gone permanently** (§6.2).
- Rationale: the descend-or-extract choice has real weight, and a high skill ceiling in combat makes
  the risk feel earned rather than arbitrary.

## 11. Castle (meta hub)

- **Hub functions** unlocked by repairing rooms with resources (gold, stone, relics) brought from runs:

| Room | Unlocks |
|---|---|
| Barracks | Roster cap, follower training |
| Forge | Upgrade/reroll gear |
| Library | Store skillbooks, copy them (costly) |
| Chapel | Revive fallen followers (if permadeath) |
| Walls / Gate | Siege defense HP, choke points |
| War Room | See next siege composition, threat level |
| Towers | Siege defense turrets / archer posts |

- **Stash:** Persistent inventory. Loadout selection before each run.
- Castle should visually transform as it's repaired — big motivator.

## 12. Siege defense

- **Trigger:** Threat clock — every N runs (e.g. 3), shown in War Room. Not random, so the player can prepare.
- **Gameplay:** Same combat system, in the castle map. **Whole roster participates** (not just the run party)
  — this is the payoff for collecting followers you don't take into the dungeon.
  - Place followers at positions (gate, walls, keep) before the wave.
  - Control swaps between them during the fight.
  - Repaired structures (walls, towers, traps) matter.
- **Outcome:** Win → reward (relics, rare recruit). Lose → castle rooms damaged (need re-repair),
  maybe loot stolen. **Not game over** — avoid a single-point fail state that wipes hours.

## 13. Design decisions & open questions

### Decided (2026-10-10)

| Topic | Decision |
|---|---|
| Death penalty | **Hardcore:** unbanked loot lost on death; followers permadie (§6.2, §10.1). |
| Hero | **Fixed character**, always in party; hero death ends the run. |
| Co-op | **No** for now. Single-player architecture. |
| Resolution | **Undecided — test several** (640×360, 960×540, 1280×720, 1920×1080 base) for look and perf in M0/M2. |
| Tactical slow-mo for orders | **Test in M3.** |

### Still open

1. **Siege frequency & failure severity.**
2. **Art style** — follows from the resolution test (pixel art vs. hi-res 2D).
3. **Lingering wounds** — include or not (§6.2).
4. **Mid-biome extraction points** — or boss-only?

## 14. Scope guardrails

- v1 prototype: 1 biome, 1 boss, 6 enemy types, 4 weapon types, 3 follower classes, castle with 3 rooms, 1 siege.
- No multiplayer, no full procgen, no crafting trees, no dialogue systems beyond simple text boxes.
- Placeholder art (shapes + colors) until combat feel is proven.
