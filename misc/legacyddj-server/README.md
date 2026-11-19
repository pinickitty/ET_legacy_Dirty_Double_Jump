# Dirty Double Jump - server setup

The configuration of the Dirty Double Jump test server, as it runs with release `v2.86.2-ddj1.3`.
Passwords are replaced by `CHANGE_ME` and the server address by `YOUR.SERVER.IP`.

## Layout

The server uses the official ET: Legacy 2.86.2 dedicated server (`/usr/local/bin/etlded.x86_64`,
identical to the etlegacy.com release). The mod lives only in its own
folder `legacyddj`, so players load `legacyddj` + `etmain` and never the stock `legacy` folder (a stock
`legacy_v2.86.2.pk3` there would otherwise win over the mod's client code).

```
/home/27965/                     fs_basepath = fs_homepath, started by cmd (systemd ets@.service)
  cmd                            start script: etlded.x86_64, +set fs_game legacyddj,
                                 +set db_uri "legacyddj/etl.db", exec etl_server.cfg
  etmain/etl_server.cfg          server settings, including the Dirty Double Jump cvars
  etmain/legacy.cfg              stock ET: Legacy server defaults (friendly fire, team limits, omnibot_path edited)
  etmain/objectivecycle.cfg      map rotation
  legacyddj/                     the mod
    legacy_v2.86.2-ddj1.3.pk3    -> symlink to /home/ftp/legacyddj/legacy_v2.86.2-ddj1.3.pk3
    qagame.mp.x86_64.so          server game library (also qagame.mp.i386.so, qagame_mp_x86/x64.dll)
    DirtyDoubleJump_<version>.txt  change list of the installed release
    etl.db                       ET: Legacy database (schema 4; writable by the server user)
    mapcfgs/default.cfg          executed at every map load: it overrides etl_server.cfg / legacy.cfg,
                                 so keep friendly fire and the team limits here in step
    omni-bot/                    Omni-Bot (omnibot_path "./legacyddj/omni-bot"); two omni-bot.cfg copies
                                 (et/user and omni-bot/et/user) - keep both the same
/home/ftp/legacyddj/             web root folder for player downloads (sv_wwwBaseURL)
```

## Dirty Double Jump settings used

| cvar | value | meaning |
|---|---|---|
| `g_tripmines` | 1 | engineers get a tripmine |
| `g_friendlyFire` | 929 | 1 FF on + 32 teammates don't trip landmines + 128 teammates don't set off tripmines + 256 you can't set off your own mines + 512 mines never hurt teammates or you |
| `g_damageweapons` | 32 | tripmines can be shot |
| `g_poison` | 1 | poison needle on (teammates can't be poisoned: no bit 16) |
| `g_poisonClasses` | 0 | all classes get the needle |
| `g_poisonLevel` | 4 | at Light Weapons level 4 |
| `team_maxTripmines` | 3 | armed tripmines per team (the HUD counter counts down from this) |
| `team_maxLandmines` | 8 | landmines per team |
| `team_maxRiflegrenades` / `team_riflegrenades` | -1 / -1 | Garand / K43 with rifle grenades for engineers, no limit |
| `team_maxSoldiers` | -1 | no class limit |
| Omni-Bot | MinBots = MaxBots = 12, CurrentDifficulty 3, moveskill 3 | in `omni-bot.cfg` |

Every cvar and bit is described in [docs/ddj-changes.txt](../../docs/ddj-changes.txt), which is also
shipped inside each pk3 as `DirtyDoubleJump_<version>.txt`.
