# NitMod 2.3.5 poison weapons: behavioural analysis (clean-room spec)

The method is the same as for the air jump and the tripmine. We read the unstripped NitMod 2.3.5 Linux
binaries in REA (Ghidra 12.1.4) and wrote down behaviour only; no decompiled code is reproduced here.
Offsets are given only where they identify a field.

NitMod has **three** poison features. They share one "poisoned" player state but work differently:

| Feature | NitMod weapon | Means of death | Who gets it | What it does |
|---|---|---|---|---|
| **Poison syringe** | `WP_POISON_SYRINGE` (47), `poison.weap` | `MOD_POISON` (59) | any class, see 1.4 | injects an enemy: lasting damage over time ("poisoned") |
| **Poison gas mine** | `WP_POISON_MINE` (51), `landmine_pgas.weap` | `MOD_POISONGASMINE` (68) | engineer, `g_weapons` bit `0x4000` | a landmine that releases a poison gas cloud instead of exploding |
| Poison gas bomb | `WP_POISON_BOMB` (50), `poisongas.weap` | `MOD_POISONGAS` (67) | covert ops, `g_weapons` bit `0x2000` | a thrown grenade that releases the same gas cloud |

Two other features reuse the poisoned state: the admin command `!poison <player>`
(`G_shrubbot_poison`), and poisoned throwing knives (`MOD 63` with `g_weapons` bit `0x800`).

---

## 1. Poison syringe (and the "poisoned" state)

### 1.1 Injecting (`Weapon_Poison`, called from `FireWeapon` for weapon 47)
- Trace **64 units** from the eye, with the same lean/prone muzzle adjustment as the medic syringe, using a historical
  (lag-compensated) trace against solid, bodies and corpses.
- It needs a **player** (client number below 64) who is **not** spawn-protected.
- **Friendly fire:**
  - If friendly fire is off (`g_friendlyFire` bit 1 clear) and the gametype is not 8, teammates
    can't be poisoned.
  - Otherwise anyone can, and a sound event (8, the "gasp") plays on the victim.
- **Effect on the victim:**
  - Sets the player flag `EF_POISONED` (`0x200000` in `ps.eFlags`).
  - Records the **poisoner** (attacker entity number) and the **start time** of the poisoning.
  - Sets the **poison stack** to 1. If the victim is already poisoned, the poisoner is updated and
    the stack goes up by 1, so every extra injection makes the poison stronger.
- **On a miss:** the ammo is refunded (the clip goes back up). A hit counts towards the medic stats.

### 1.2 Damage over time (`ClientThink_doPmove`, every client frame)
While `EF_POISONED` is set, and each time the next-tick time has passed:

| Setting | Default (`g_poison` bit 4 clear) | `g_poison` bit 4 set |
|---|---|---|
| Damage per tick | **1 × stack** | **10 × stack** |
| Tick interval | **50 ms**, so 20 HP/s per stack | **1500 ms** |

- Weapon-table overrides for the poison syringe's damage and interval replace these values when they are set.
- Damage is dealt with `G_Damage(victim, poisoner, poisoner, no direction, MOD_POISON)`, so kills
  are credited to the poisoner. A poisoner who has gone (number −1) means no attacker.
- `MOD_POISON` hits don't count as hits in the stats, play no hitsounds and give no damage kick.

### 1.3 Curing
- **Health packs** (`Pickup_Health`):
  - Cure poison if `g_poison` bit **2** is set. Curing clears the flag, the stack and the poisoner.
  - If `g_poison` bit **8** is also set, a pack dropped by **your own poisoner** does not cure you.
- **Health cabinets** (`heal_touch`): cure when `g_poison` bit 2 is set.
- **Death or respawn:** the state is cleared with the player state (the normal reset).
- **Self-kill is refused while poisoned** ("Selfkill disabled while you are poisoned.").

### 1.4 Who gets it (`G_AddClassSpecificTools`)
- Given at spawn when `g_poison` ≠ 0 **and** the player has **Light Weapons level 4**, whatever their class.
  Confirmed in `G_SetPlayerSkill`: NitMod keeps a per-skill bitmask of the levels reached
  (`0x02` = level 1 … `0x10` = level 4, `0x20` = level 5), and the syringe check reads bit `0x10` of skill 4 (Light Weapons).
- It is given regardless of class: the check comes after the class-specific tools.

### 1.5 `g_poison` bits (as far as observed)
| Bit | Meaning |
|---|---|
| any non-zero | poison syringe enabled |
| `2` | health packs and cabinets cure poison |
| `4` | slow poison: 10 HP every 1.5 s instead of 1 HP every 50 ms |
| `8` | the poisoner's own health packs don't cure |

### 1.6 Client
- `sprites/poisoned` is shown over poisoned players, read from the `EF_POISONED` entity flag.
- `sound/player/gasp.wav` plays on injection (server sound event 8).
- Obituaries: "was poisoned by", and "poisonned himself" (*sic*) for a self-kill.
- Assets: the `weapons/poison.weap` syringe uses poison skins (`models/multiplayer/syringe/poison_*.skin`,
  `syringepoison.tga`, `gfx/misc/poisonfluid.tga`).

---

## 2. Poison gas mine

### 2.1 Placing and arming: exactly a landmine
- **Throwing:** `FireWeapon` treats weapon 51 like the landmine: same charge cost (`chargeCost_Landmine`) and
  the same grenade-style throw.
- **On landing (`fire_grenade`, cases 25 and 51 together):**
  - classname `landmine`; `teamNum` = team + 4 (unarmed)
  - same box (±16), contents, health 5 and takedamage
  - added to the **same landmine list**, so it counts towards **`team_maxLandmines`**
  - only the **means of death differs**: 68 (`MOD_POISONGASMINE`) instead of 40
- **Arming and defusing:** the landmine pliers code. Defusing returns a weapon-51 mine to a poison-mine
  owner (otherwise a normal landmine), and Covert Ops spotting, markers and the map icon work as for landmines.
- **Markers:** it uses its own markers (`mine_marker/*_marker2`).

### 2.2 Triggering (`LandMineTrigger`)
- A normal landmine waits for the player to step off (`LandminePostThink`) and then explodes.
- A **poison mine** instead:
  - plays sound event 11 (the gas release)
  - after **1000 ms** becomes a **gas cloud**: its think switches to the poison branch of the
    smoke-bomb code (section 3)
  - like a landmine, gets `teamNum += 8` (triggered) and a trigger time
- **No explosion and no screen shake:** weapon 51 is not in the explosion-shake list.

---

## 3. The poison gas cloud (shared by the poison mine and the poison bomb)

The cloud is the smoke-grenade entity running a poison branch (`weapon_smokeBombExplode` →
`nitmod_PoisonGasThink`):

| Time since release | Cloud radius (`s.effect1Time`, drawn by the client like smoke) |
|---|---|
| 0–1 s | grows: 16 + 0.624 × ms, so 16 → about 640 |
| 1–16 s | 640 |
| 16–18 s | −1 (dissipating) |
| > 18 s | entity removed |

- **Think rate:** every **800 ms**.
- **Damage:** once the radius is above 24, each think deals radius damage with
  - damage = the weapon's damage value
  - radius = the weapon's splash radius (not the visual cloud radius)
  - means of death = `MOD_POISONGASMINE` or `MOD_POISONGAS`, attacker = the mine's or bomb's owner
- **What it hurts** (`G_RadiusDamage`):
  - gas only hurts **players**; objects, constructibles and props are skipped
  - normal distance falloff
  - targets out of line of sight but within 20% of the radius take 10%
- **Gas does not apply the lasting `EF_POISONED` state.** It is direct damage while you stand in it.
- **Obituaries:** "'s Poison Gas", "'s own poison gas landmine", and for self-kills "choked on his own
  poison gas" / "choked on his own poison gas landmine".

---

## 4. Open points

- **Syringe skill condition:** resolved: Light Weapons level 4 (see 1.4). The port uses this rule.
- **Weapon values:** the gas damage and splash radius come from NitMod's weapon table, which was not read.
  Sensible defaults need choosing (for example damage 10–15 per 0.8 s tick, radius around 250).
- **Client screen effect:** apart from the sprite and the sound, the client-side "poisoned" view effect
  (if there is one) was not traced.

## 5. What a port to ET Legacy 2.86.2 would involve

| Part | Work | Size |
|---|---|---|
| Poisoned state | `EF_POISONED` (a free `ps.eFlags` bit in ETL must be found), client fields for poisoner/start/stack, the timed tick in `ClientThink`, `MOD_POISON`, cures in health pickup and cabinet, self-kill block, reset on spawn | medium |
| Poison syringe | new `WP_POISON_SYRINGE` (57) using `Weapon_Syringe`-style tracing, `g_poison` cvar and bits, the loadout rule (our choice, e.g. medics or covert ops), the `sprites/poisoned` icon | medium |
| Gas cloud | a poison branch of ETL's `weapon_smokeBombExplode` with a radius-damage tick, `MOD_POISONGASMINE` | small |
| Poison gas mine | new `WP_POISON_MINE` (58) reusing the whole landmine path (throw, arm, defuse, spotting, team limit); the only change is the trigger handing over to the gas cloud | small–medium |
| Client | obituaries, `sprites/poisoned`, gasp sound, the green-tinted gas (smoke drawing with a colour), weapon files, models and skins | medium |
| Assets | from `nitmod_2.3.5.pk3`, needing the same credit and permission as the tripmine model: poison syringe skins and textures, `plandmine.md3`/`v_plandmine.md3`, `iconw_plandmine_1_select`, `*_marker2`, `sprites/poisoned.tga`, `pgasbomb.md3` (only needed for the bomb) | — |

The poison mine is the easier of the two features you asked for, because it is almost entirely
ETL's existing landmine plus ETL's existing smoke cloud. The syringe needs the new "poisoned"
player state, which the cures and the client also depend on.
