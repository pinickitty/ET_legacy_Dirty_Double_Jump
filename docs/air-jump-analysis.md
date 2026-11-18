# ET:Legacy – Dirty Double Jump: how the air jump was found, isolated and ported

Branch `air-jump-2.86.2` on <https://github.com/pinickitty/ET_legacy_Dirty_Double_Jump>
(head `2a8ad609d`, built version `v2.86.2-6-g2a8ad60`).

## 1. Method: clean-room (specification first, then implementation)

The work had two strictly separated halves:

1. **Analysis.** We studied NitMod's binaries in REA (a Ghidra 12.1.4 back end) and wrote down only
   *behaviour*: conditions, constants, flag bits, where things are called and in what order.
2. **Implementation.** We wrote the feature in ET Legacy 2.86.2 from that written spec, in ETL's own
   style and with ETL's own helpers. No decompiled code was copied, and that rule held from the
   start ("implement from this spec, never copy decompiled code").

This is also why this repository contains **no decompiled NitMod source**. NitMod is closed-source and
third-party, so its decompiled output is a derivative of their code. Republishing it (and especially
pushing it to a public fork) would undo the clean-room separation. You can reproduce any of the
analysis below yourself: open the files listed in section 2 in Ghidra/REA and go to the named
functions.

## 2. Inputs

| File | What it is | SHA-256 |
|---|---|---|
| `qagame.mp.i386.so` | NitMod 2.3.5 server, Linux i386, **not stripped** | `84a7e795…ef49` |
| `cgame.mp.i386.so` | NitMod 2.3.5 client, Linux i386, not stripped | `45db79d5…e7f` |
| `qagame_mp_x86.dll`, `cgame_mp_x86.dll` | NitMod 2.3.5 Windows (first analysis, stripped) | `2e3c2cb2…`, `f2683822…` |
| `etl_*.so`, `etl_*_mp_x86.dll` | Official ET Legacy 2.86.2, used as a "what's stock" baseline | — |

Full hashes: qagame.so `84a7e7958952f804d65fbe6db6b4758ea0cf6b596b26a514a68de0ba3bd9ef49`,
cgame.so `45db79d57b58d3a530c6fc7abbc39613accdb8d1804a2e3cb15324cee5fece7f`.
The NAS copies REA used (`/share/CACHEDEV1_DATA/cont_conf/rea/samples/`) were confirmed byte-identical.

## 3. Identification: finding the feature

**Windows pass (the original spec).** The DLLs are stripped, so the entry point was the cvar
*string* `g_doubleJump`. We followed xrefs from the string to the cvar table, from the cvar's value
slot to its readers, and from there into the player-movement code. In that code we matched the
surrounding structure (friction, gravity and the step-slide calls) against ETL's `bg_pmove.c` to
recognise `PM_AirMove`.

**Linux pass (verification).** The `.so` files keep their symbols, so they gave a stronger check:

1. `search_procedures` for `(double|air).?jump`, `PM_AirMove`, `PM_GroundTrace` and `PM_CheckJump`
   found **no dedicated double-jump function**. The logic is inlined into `PM_AirMove`
   (qagame `0x38360`).
2. `find_xrefs_to_name g_doubleJump` / `g_DJHeight`, plus `search_strings` for the cvar names, located
   the cvar registration. Only qagame has these strings, so cgame must receive the values another way.
3. The xrefs from the cvar value slots led into two NitMod helpers, `nitmod_SimpleCS` and
   `nitmod_SendNCS`. Their callers (`procedure_callers`) are `G_InitGame`, `G_UpdateCvars` and
   `ClientCommand`. This is how the values reach clients.
4. `procedure_pseudo_code PM_AirMove` and `PM_GroundTrace` were read in **both** qagame and cgame. The
   code is the same `bg_pmove.c` compiled into both, as in stock ETL.

## 4. Isolation: separating NitMod's additions from stock ETL

We compared each function against the ETL 2.86.2 source we were porting to, line by line. Whatever
had no counterpart in stock ETL is the feature:

**In `PM_AirMove`, before the friction call (new block):**
- Gate: mode ≠ 0, the player isn't prone (`EF_PRONE`), and `pm_flags & 0x280` is clear. That is
  `PMF_RESPAWNED` (512) plus a **new bit 128** (NitMod's "already air-jumped" flag).
- Mode 2 additionally requires `velocity[2] > 0` (only on the way up). Mode 1 allows the jump at any time.
- Input: `upmove >= 10`. If `PMF_JUMP_HELD` is set, zero `upmove` and refuse (the player must
  release and press jump again).
- Effect: clear `pml.groundPlane` and `pml.walking`; set `PMF_JUMP_HELD` and bit 128;
  `groundEntityNum = ENTITYNUM_NONE` (1023); `velocity[2] = height × 270` (270 = `JUMP_VELOCITY`).
  This *replaces* the vertical speed rather than adding to it.
- Stamina: if ≥ `PM_JUMP_DELAY` (850 ms) since the last charged jump, subtract 2500 sprint (minimum 0)
  and restart that timer. `ps->jumpTime = now` is set either way, which is the same rule as a
  ground jump.
- Animation: the jump or backward-jump animation event.
- A `waterlevel > 1 → PM_WaterMove` branch exists but can never run, because `PM_AirMove` is only
  reached with `waterlevel ≤ 1`.

**In `PM_GroundTrace` (one added line):** bit 128 is cleared only on **walkable** ground, after
the steep-slope and kick-off early returns. Landing on a steep slope therefore does not recharge
the jump.

**Settings:** `g_doubleJump` (default `0`, flags 0) and `g_DJHeight` (default `1.4`), pushed to
clients by NitMod server commands (`scs` field 1, `#` field 15, `%.3f`). cgame stores them in `cgs`
and feeds them to its prediction pmove.

**Check that bit 128 is free in ETL:** `pm_flags` is networked as 16 bits (`msg.c`), and 128 is
unused in ETL 2.86.2's `PMF_*` list. No `playerState_t` change and no protocol change are needed.

## 5. Integration into ET Legacy 2.86.2 (commit `adf0f50`, plus build commits)

| File | Change |
|---|---|
| `src/game/bg_public.h` | `#define PMF_AIRJUMPED 128`; `pmove_t` gains `int airJump; float airJumpScale;` |
| `src/game/bg_pmove.c` | new `static qboolean PM_CheckAirJump(void)` implementing section 4. `PM_AirMove` calls it first and applies the stamina rule. `PM_GroundTrace` clears `PMF_AIRJUMPED` after `pml.walking = qtrue`. The animation uses ETL's existing `PM_PlayJumpAnim()` |
| `src/game/g_cvars.c/.h`, `src/cgame/cg_cvars.c/.h` | `g_airJump "0"` and `g_airJumpScale "1.4"`, both `CVAR_SYSTEMINFO`, mirrored like `pmove_fixed` |
| `src/game/g_active.c` | copies the cvars into the server `pmove_t` |
| `src/cgame/cg_predict.c` | copies the cvars into `cg_pmove`, so client prediction matches (no `cg_showmiss` errors) |

**Deliberate differences from NitMod (behaviourally neutral):**
- Transport: ETL's standard `CVAR_SYSTEMINFO` instead of NitMod's server commands. The client sees
  the exact float instead of a 3-decimal rounded value.
- Cvar names: `g_airJump` / `g_airJumpScale`. They map 1:1 to `g_doubleJump` / `g_DJHeight`.
- Animation: ETL's `PM_PlayJumpAnim` (it also plays the backward animation when standing still and
  sets `PMF_BACKWARDS_JUMP`). This affects how it looks, not how the player moves.

**Packaging and build changes (not part of the feature):**
- `MOD_FOLDER=legacyddj` (CMake → cgame/ui → `i18n.c`), so menus translate in a custom folder
  instead of showing raw `MSGID_` keys.
- `ETL_HIDE_DEVELOPMENT_BUILD` removes the watermark.
- `misc/description.txt` carries the coloured name `^1ET^7:Legacy^1 -^7 Dirty Double Jump`.
- easybuild resolves redirected Documents/Desktop folders.
- Builds:
  - Windows x86/x64: MSVC 14.44
  - Linux i386 client: Ubuntu 24.04
  - Linux server and x86_64: AlmaLinux 8 (glibc 2.28)
- Single pk3 `legacy_v2.86.2_dirty.pk3` with all 8 cgame/ui libraries; the qagame libraries sit beside it.

## 6. Usage

```
set g_airJump 1          // 0 off, 1 any time in the air, 2 only while rising
set g_airJumpScale 1.4   // air-jump speed = 270 × scale
```
Server: `./etlded +set fs_game legacyddj +set g_airJump 1 +map oasis`
