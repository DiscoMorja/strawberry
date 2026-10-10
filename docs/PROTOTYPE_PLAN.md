# Prototype Plan

Goal: validate the riskiest ideas first, cheapest first. Each milestone ends in a **playable build
that answers one question**. If the answer is "no, not fun", fix or pivot *before* moving on.

Engine: Godot 4.7, GDScript, 2D. Placeholder art (colored shapes) until M3 is fun.

---

## Risk ranking (what to prove first)

| # | Risk | Why it's risky | Proven in |
|---|---|---|---|
| 1 | Vermintide melee feel in top-down | Feel came from first-person aim/audio | M1 |
| 2 | Hordes (100+) + readability + perf | Chaos hides specials; Godot physics cost | M2 |
| 3 | Party control inside horde chaos | Swapping/commands can feel clunky | M3 |
| 4 | Run loop is compelling | Rooms/loot pacing | M4 |
| 5 | Castle + siege makes meta worthwhile | Base-building can feel like chores | M5 |

Narrative, the Wizard, multiple biomes and content volume are **low risk** — do them last.

---

## M0 — Foundation (½–1 day)

- Folder structure (below), input map (KB+M and gamepad), physics layers.
- Debug overlay: FPS, enemy count, hitbox visualization toggle, time-scale slider, spawn hotkeys.
- Grey-box arena scene with camera (smooth follow, small look-ahead toward aim).
- **Resolution test harness:** debug hotkey cycling base viewport 640×360 / 960×540 / 1280×720 / 1920×1080
  (stretch mode `canvas_items` vs `viewport`). Compare readability and perf; re-run in M2 with 150+ enemies.

## M1 — Combat feel sandbox (1–2 weeks) ← most important

**Question: Is fighting 1 elite and 20 trash fun with one hero?**

- Hero: move, aim, light chain, charged heavy, block (frontal arc, stamina pips), push, dodge.
- Attack data as `Resource`: wind-up / active / recovery, arc, range, damage, cleave, stagger.
- Enemies: Trash (low mass) and Elite (high mass, telegraphed heavy attack).
- Systems: hitbox/hurtbox, cleave budget, stagger tiers, guard break, crit window during enemy wind-up.
- Juice (non-negotiable here): hit-stop, screen shake, knockback, hit flash, damage numbers, placeholder SFX.
- Tuning: expose all numbers in resources; time-scale slider for inspecting.

**Exit criteria:** You enjoy playing the sandbox for 10 minutes with no goal.

## M2 — Horde & specials (1–2 weeks)

**Question: Can I read the fight and make priority choices with 100+ enemies on screen at 60 fps?**

- Spawner + simple **Director** (build-up → horde → relax; separate special timer).
- Enemy roles: Trash, Shielded, Elite, + 2 specials (Ranged archer, Disabler/grabber).
- Movement at scale: **flow field** toward the party on a grid (one path calc, all trash reads it)
  + cheap separation. NavigationAgent2D only for elites/specials.
- Attack token system (limit simultaneous attackers per target).
- Readability: special spawn audio cue + off-screen indicators, ground telegraphs, outline on priority targets.
- Perf pass: profile at 200 enemies; pool enemies; avoid per-enemy `_physics_process` heavy work.

**Exit criteria:** Stable 60 fps at 150 enemies; a playtester naturally prioritizes specials.

## M3 — Party (1–2 weeks)

**Question: Does controlling a party feel good during a horde, not just in calm moments?**

- 2 followers (e.g. Shield-bearer, Archer) using the *same* character scene as the hero with an AI "brain" swapped in.
- `Tab` swap control (camera blends); AI takes over the previous character.
- Orders: Follow / Hold / Focus target / Regroup. Stances: Aggressive / Defensive.
- Downed + revive, follower permadeath, basic service record (kills, runs survived).
- Experiment: tactical slow-mo while holding the command key.

**Architecture key:** Character = body + components; *controller* is pluggable
(`PlayerController` or `AIController`). Swapping control = swapping controller. Do this right and party control is cheap.

**Exit criteria:** Playtesters use Focus and Swap without being told to.

## M4 — Run loop vertical slice (2–3 weeks)

**Question: Is one 20-minute run with progression in it compelling?**

- Room chain: 8 handmade rooms + branching exits with room-type icons.
- Room types: Combat, Treasure, Recruit, Library, Rest, Boss.
- Loot: 4 weapon archetypes, armor, 1 trinket slot, ~10 affixes. Inventory + equip UI per character.
- 3 skillbooks (e.g. Whirlwind, Shield Bash, Volley).
- Boss 1 (Crypts): 2 phases, adds spawn, telegraphed big attacks.
- Death / extract → results screen.

**Exit criteria:** Testers want to start another run immediately.

## M5 — Castle & siege (2–3 weeks)

**Question: Does returning to the castle make runs more meaningful?**

- Castle hub scene: stash, roster, loadout selection, 3 repairable rooms (Barracks, Forge, Walls), Memorial Wall.
- Save/load (JSON or `ResourceSaver`) — stash, roster, castle state, threat level.
- Threat clock → siege every ~4 runs. Bastion (castle HP): siege loss drains it, 0 = campaign over. Siege map with gate/wall positions, whole roster deployed.
- Scripted prologue siege + Wizard shockwave (simple cutscene: freeze, flash, text box).
- Threat level scales dungeon stats.

**Exit criteria:** Full loop playable start to second siege; testers care about losing castle rooms.

## M6+ — Content & polish

Second biome + boss, more enemies/specials, follower traits, more affixes and skills,
real art pass, audio, story beats, balancing. Only after M1–M5 are fun.

---

## Proposed project structure

```
res://
  addons/                 # (existing) godot_ai
  docs/                   # GDD, plans
  core/                   # autoloads: Game, Events (signal bus), SaveManager, Director
  combat/
    attack_data.gd        # Resource: timings, arc, damage, cleave, stagger
    hitbox.gd / hurtbox.gd
    health_component.gd
    stagger_component.gd
    stamina_component.gd
  characters/
    character.tscn/.gd    # shared base for hero + followers
    controllers/
      player_controller.gd
      ai_controller.gd
    classes/              # ClassData resources
  enemies/
    enemy_base.tscn/.gd
    roles/                # trash, shielded, elite, archer, grabber ...
    flow_field.gd
  items/
    item_data.gd, weapon_data.gd, affix_data.gd, skillbook_data.gd
    data/                 # .tres item definitions
  dungeon/
    rooms/                # handmade room chunks
    run_manager.gd
  castle/
    castle.tscn, siege.tscn
  ui/
  debug/
```

## Tech conventions

- **Composition over inheritance:** small components (Health, Stagger, Stamina, Hitbox) as child nodes.
- **Data-driven:** every weapon, enemy, item, skill is a `Resource` (`.tres`) — tuning without code.
- **Signal bus autoload** (`Events`) for cross-system events (`enemy_died`, `special_spawned`, `character_downed`).
- **State machines** for character action states (Idle, Move, Attack, Block, Dodge, Staggered, Downed).
- **Physics layers:** 1 World, 2 Party bodies, 3 Enemy bodies, 4 Party hitboxes, 5 Enemy hitboxes, 6 Hurtboxes, 7 Pickups.
- **Static typing** in GDScript everywhere (perf + fewer bugs).
- **Git from day one:** https://github.com/DiscoMorja/strawberry

## Immediate next steps

1. ~~`git init` + first commit.~~ Done.
2. M0: input map, physics layers, debug overlay, grey-box arena.
3. M1: hero character with light/heavy/block/dodge and a training dummy, then trash + elite.
