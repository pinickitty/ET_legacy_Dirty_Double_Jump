# Dirty Double Jump - server setup

The configuration of the Dirty Double Jump test server, as it runs with release `v2.86.2-ddj1.0`.
Passwords are replaced by `CHANGE_ME` and the server address by `YOUR.SERVER.IP`.

## Layout

The server uses the official ET: Legacy 2.86.2 dedicated server (`etlded`). The mod lives only in its own
folder `legacyddj`, so players load `legacyddj` + `etmain` and never the stock `legacy` folder (a stock
`legacy_v2.86.2.pk3` there would otherwise win over the mod's client code).

```
/home/27965/                     fs_basepath = fs_homepath, started by cmd (systemd ets@.service)
  cmd                            start script: +set fs_game legacyddj, exec etl_server.cfg
  etmain/etl_server.cfg          server settings, including the Dirty Double Jump cvars
  etmain/legacy.cfg              stock ET: Legacy server defaults (g_friendlyFire, omnibot_path edited)
  etmain/objectivecycle.cfg      map rotation
  legacyddj/                     the mod
    legacy_v2.86.2-ddj1.0.pk3    -> symlink to /home/ftp/legacyddj/legacy_v2.86.2-ddj1.0.pk3
    qagame.mp.x86_64.so          server game library (also qagame.mp.i386.so, qagame_mp_x86/x64.dll)
    mapcfgs/default.cfg          executed at every map load: keep g_friendlyFire here in step with etl_server.cfg
    omni-bot/                    Omni-Bot (omnibot_path "./legacyddj/omni-bot")
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

Every cvar and bit is described in [docs/ddj-changes.txt](../../docs/ddj-changes.txt), which is also
shipped inside each pk3 as `DirtyDoubleJump_<version>.txt`.
