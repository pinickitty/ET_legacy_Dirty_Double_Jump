# NitMod 2.3.5 tripmine: behavioural analysis (clean-room spec)

The analysis used the same method as the air jump (see `air-jump-analysis.md`). We read the NitMod
binaries in REA (Ghidra 12.1.4) and wrote down **behaviour only**; no decompiled code is reproduced
here. The unstripped Linux builds (`qagame.mp.i386.so` SHA-256 `84a7e795…ef49`, `cgame.mp.i386.so`
`45db79d5…e7f`) gave the function names. The Windows `qagame_mp_x86.dll`/`cgame_mp_x86.dll`
contain the same feature: the same cvars, the `tripmine.weap` file and the same messages.

## 1. What it is

The tripmine is a separate **engineer weapon** (`weapon_tripmine`, `tripmine.weap`, `MOD_TRIPMINE`).
In NitMod it is weapon number 49. The engineer plants it on a wall, then arms it with pliers like a
landmine. Once armed, it projects an invisible-to-enemies laser along the wall normal and explodes
when an enemy breaks the beam.

## 2. Functions involved (qagame)

| Function | Role |
|---|---|
| `FireWeapon` | the weapon-49 case calls `nitrox_tripmine` |
| `nitrox_tripmine` (0x10c320) | checks the placement is valid, the team limit and the charge cost |
| `G_PlaceTripmine` (0x101bf0) | spawns the unarmed mine entity |
| `Weapon_Engineer` (0x104550), tripmine case | arms and defuses it with pliers |
| `G_TripMinePrime` (0x9e050) | makes the mine live 250 ms after arming |
| `G_TripMineThink` (0x9a920) | runs the beam trace every 100 ms and fires the mine |
| `Nit_WeapDie` | explodes the mine when it is shot to 0 health |
| `nitmod_CountTeamTripmines` / `nitrox_RemoveTripmines` | team limit / owner cleanup |

**cgame:** `CG_ProcessEntity` sends entity type 34 to `CG_Bomb`, which draws the mine and its beam.

## 3. Placement (fire button with the tripmine selected)

1. Trace **64 units** from the eye along the view direction (mask = solid + bodies + corpses). The
   trace must hit the **world** (entity 1022), not sky and not a no-impact surface (surface flags
   `0x14`). Otherwise: "Tripmine cannot be placed here...".
2. Trace a second time from the hit point **along the surface normal, 512 units**. It must also hit
   the world, which means a facing wall exists within 512 units. Otherwise the same message.
3. Team limit: the count of the team's **armed** mines must be below `team_maxTripmines`. Otherwise:
   "Your team has too many tripmines placed...".
4. Charge cost: `chargeCost_Tripmine` (a per-skill-level table, like the landmine), deducted at this point.
5. Spawn the entity:
   - classname `tripmine`, entity type 34, `weapon` = tripmine, `SVF_BROADCAST`, parent = the planter
   - damage, splash damage and splash radius come from the weapon table; MOD and splash MOD = `MOD_TRIPMINE`
   - bounding box ±4 × ±4 × ±3, contents `CONTENTS_CORPSE`
   - origin = hit point; `origin2` = surface normal (the beam direction)
   - `teamNum` = planter team **+ 4** (the ETL landmine convention for "not armed")
   - think = free the entity after **15 s**, so an unarmed mine vanishes
   - message: "Tripmine is set, but NOT armed!"; the mine is added to a global tripmine list

## 4. Arming and defusing (engineer pliers, inside `Weapon_Engineer`)

The progress counter goes from 0 to 255, like the landmine and dynamite.

- **Unarmed mine, own team:** if the team is still below `team_maxTripmines`, add the
  `armSpeed_LandMine` skill value per pliers hit and print "Arming Tripmine..." at most every 3 s.
  At 255: "Tripmine armed", `teamNum` = the team (so it now counts toward the limit),
  `effect1Time = 1`, and think = `G_TripMinePrime` in 250 ms. If the limit has been reached, the
  mine is removed with "Your team has too many tripmines placed...".
- **Unarmed mine, enemy team:** "You cannot arm an enemy team tripmine..." (at most every 3 s).
- **Armed mine (either team):** after its arm time, add the `armSpeed_Dynamite` skill value. The
  message is "Disarming Tripmine...". At 255 the mine is removed with "Tripmine disarmed". Defusing
  an **enemy** mine gives **4 XP** in engineering ("defusing an enemy tripmine").

## 5. Live mine

**`G_TripMinePrime`** runs once:
- the mine becomes damageable with **health 20**
- die → `Nit_WeapDie`, which removes the contents, sets think = explode and arms the next frame
- think = `G_TripMineThink`

**`G_TripMineThink`** runs every **100 ms**:
- Sets `effect1Time = 2` (active).
- The beam runs from the origin along the normal for **2048 units**. A smoke grenade's cloud
  covering the beam stops it working that tick.
- Trace the beam with the shot mask. Then:
  - **Hit a player:**
    - If `g_friendlyFire` bit `128` is set, a teammate who is **not** the owner doesn't trigger it.
      This is the inverse of what you might expect: the owner and enemies always trigger it.
    - If `g_OmniBotFlags` bit `32` is clear, bots on the same team don't trigger it.
    - Otherwise, think = explode.
  - **Hit a non-player:** it triggers only for two specific entity classes (matched by classname
    hash, probably corpses/bodies) or when an internal per-entity flag is set. Otherwise it is ignored.
- The explosion is the normal missile explosion (`G_ExplodeMissile`), using the damage, splash and
  MOD set at placement.

**Cleanup:** if `n_tripmineTimeout` ≠ 0, all of a player's mines are removed when they disconnect,
change team (`SetTeam`), are shuffled (`G_shuffleTeams`), or at one further call site. Removal clears
the parent first, so no kill credit or obituary follows.

**Cvars:** `team_maxTripmines` (limit per team), `n_tripmineTimeout` (remove the owner's mines),
`chargeCost_Tripmine` (cost table). It also reuses the stock `armSpeed_LandMine`/`armSpeed_Dynamite` tables.

## 6. Client (`CG_Bomb`, entity type 34)

- It draws the tripmine weapon model at the mine's position, oriented to the wall normal, with the
  usual powerup shells.
- The **beam** is drawn only when `effect1Time` ≠ 0 (armed). It is visible to the **mine's own
  team** and to spectators. Enemies see it only when a per-client flag (bit `0x10` in client info)
  is set: a reveal ability.
- The client traces 4096 units from the mine along the normal and draws a rail-core beam (the
  shader that the `misc_beam` code also uses) to the hit point:
  - **red** for Axis mines, **blue** for Allied mines
  - **dim** (50/255) while priming or when revealed to an enemy, **full** (255) when active
- HUD and chat strings: "Tripmine is set, but NOT armed!", "Arming Tripmine...", "Tripmine armed",
  "Disarming Tripmine...", "Tripmine disarmed", "You cannot arm an enemy team tripmine...",
  "Your team has too many tripmines placed...", "Tripmine cannot be placed here...",
  "One of your tripmines has been destroyed!". The obituary is "forgot where his tripmine was" for a
  self-kill, and "'s Tripmine" for a kill by someone else's mine. There is also a "First Tripmine Kill" award.

## 7. What a port into ET Legacy 2.86.2 would involve

ETL has no tripmine, and NitMod's weapon number 49 is already taken in ETL (`WP_MOBILE_BROWNING`).
A port is a new weapon, not a movement tweak like the air jump, so it is much larger:

| Area | Work |
|---|---|
| `bg_public.h` / `bg_misc.c` | add `WP_TRIPMINE` (56, under the 64 limit), `MOD_TRIPMINE`, a new entity type, the item, `weaponTable`/`modTable` entries, and engineer loadout and ammo |
| `g_weapon.c` | fire → placement checks (section 3); pliers arm/defuse branch (section 4) beside the landmine code |
| `g_missile.c` (or a new `g_tripmine.c`) | prime/think/die (section 5), the team count, the owner cleanup hooks in `ClientDisconnect`/`SetTeam`/shuffle |
| `g_cvars.c` | `team_maxTripmines`, `g_tripmineTimeout` (ETL naming), the charge-cost and skill tables |
| cgame | weapon registration, a `CG_Tripmine` draw function (section 6), obituaries, HUD/cp messages, the weapon-bank slot for engineers |
| Assets | the `tripmine.weap` weapon file, model, icon and sounds. NitMod's are its own copyrighted assets, so the port needs original or free-licensed models; a stock landmine or satchel model could stand in |
| Bots | Omni-bot mapping (optional) |

Because both cgame and qagame ship in our mod, the new weapon/entity numbers stay inside the mod and
need no engine or protocol change. Clients must have the matching pk3, which the pure server enforces anyway.

## 8. Decisions for the ET Legacy port (branch `ddj001`)

- **Entity model:** the mine is an `ET_MISSILE` with `MOD_TRIPMINE`, like ETL's landmine, satchel and
  dynamite, rather than a new entity type. The shared `entityType_t` in `q_shared.h` is therefore
  unchanged. ETL already notes the obsolete `ET_BOMB` slot as "tripmines".
- **Numbers:**
  - `WP_TRIPMINE` = 56
  - `MOD_TRIPMINE` follows `MOD_MP34`
  - `WS_TRIPMINE` = 28
  - `ITEM_WEAPON_TRIPMINE` is the last item, so no existing item index moves
- **Switch:** `g_tripmines` (default 0, latched). Engineers only get the weapon at spawn when it is 1.
  NitMod has no such switch.
- **Enemy visibility:** this replaces NitMod's unconfirmed client flag (section 6) with ETL's own
  landmine rules:
  - Own team and spectators always see the mine and beam.
  - Enemies with Battle Sense *Trap Awareness* see it within 256 units, as with landmines.
  - A mine spotted by a Covert Ops with binoculars is shown to the enemy team, as with landmines.
- **Friendly fire:** NitMod's `g_friendlyFire` bit-128 rule is dropped. Teammates never trigger
  their team's mine; the owner and enemies do.
- **Assets:** until the mine has its own model it reuses the stock landmine `.weap`, models and icons.
- **Server behaviour (T2), from the spec in sections 3-5:**
  - **Placement:** 64-unit wall trace plus a 512-unit opposite-wall trace. Placing it costs the
    same charge as a landmine, and a failed placement or a full team limit refunds that charge.
  - **Before arming:** the mine sits 4 units off the wall and disappears after 15 s if nobody arms it.
  - **Arming and defusing:** pliers use the landmine arm/defuse rates. Defusing an enemy mine is worth 4 XP.
  - **Once armed:**
    - It goes live after 250 ms (`s.time2`) with 20 HP and can be shot.
    - The beam check runs every 100 ms over 2048 units and is blocked by an active smoke cloud.
    - Only players set it off; NitMod's classname-hash entity case is not reproduced.
  - **Cleanup:** with `g_tripmineTimeout` set, the owner's mines fade on disconnect, team change and shuffle.
  - **Command map:** tripmines appear with the landmine icon.
  - **Cvars:** `team_maxTripmines` (default 6) and `g_tripmineTimeout` (default 1).
- **Client behaviour (T3), from section 6:**
  - **Drawing:** `CG_Tripmine` draws the mine flat on the wall, its top along the normal, then a
    rail-core laser from the mine to the first solid surface or player.
  - **Beam colour:** red for Axis, blue for Allies. It is dim (50) while priming or when seen by an
    enemy, and bright (255) once live for its own team.
  - **Visibility:** own team and spectators always see it. Enemies see it only if it is spotted, or
    they have Trap Awareness and are within 256 units (drawn with the construction shader, like landmines).
  - **Crosshair:** shows "X's Tripmine".
  - **Effects:** explosion, view model and the auto-switch to pliers after placing all come from the
    landmine weapon file.
- **After in-game testing:**
  - **Model:** NitMod's tripmine model, view model, textures and selected icon are bundled, credited in
    `etmain/models/multiplayer/tripmine/CREDITS.txt`. They are loaded through our own
    `weapons/tripmine.weap`, oriented forward along the wall normal and kept upright.
  - **Ownership:** the mine is owned by `ENTITYNUM_WORLD` from the moment it is placed. Traces skip
    entities owned by the tracing player, so the planter's own pliers could not reach it.
    `g_tripmineDebug 1` showed every pliers trace hitting the wall behind it.
  - **Pliers hit box:** pliers use a 12-unit real hit box, like landmines.
  - **Arming delay:** the beam goes live `g_tripmineArmTime` ms after arming (default 3000, minimum
    250), so the planter can step out of it. NitMod used 250 ms.
  - **Debugging:** `g_tripmineDebug 1` prints placement, pliers, arming, expiry, priming and trigger
    steps to the server console.
