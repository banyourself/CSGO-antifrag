# antifrag (fork)

Caps how much damage an opposing-team knife hit can do, and puts a cooldown on a CT who stabs
a T. Built for Hide and Seek, where a backstab landing for 195 ends the round instantly and
nobody has any fun. This is my fork of **HNS Anti Frag** by Gold KingZ (oqyh).

Upstream is 580 lines, this is 626.

## Install

Drop the `addons` folder into your `csgo` folder:

```
addons/sourcemod/plugins/antifrag.smx                          the compiled plugin
addons/sourcemod/scripting/antifrag.sp                         source
addons/sourcemod/translations/HNS-Anti-Frag.phrases.txt        chat strings
```

The plugin writes the phrases file itself if it is missing, so a fresh install works either
way, but the shipped copy is the one to edit. Convars land in
`cfg/sourcemod/HNS-Anti-Frag.cfg` on first run.

## The armor maths, which is why I forked it

`hns_f_knife_damage` is supposed to be the health you lose. CS:GO reduces knife damage to 85%
against kevlar, so setting 50 gave you a 42 damage stab against an armored player.

Upstream compensated for that with an eighteen-branch if/else ladder: damage under 5 got +1,
under 11 got +2, under 17 got +3, all the way to +18. Hand-tuned constants approximating a
curve.

This version does the actual calculation. Raw damage is `healthDamage / 0.85`, and there is a
second branch for nearly depleted armor, where the armor pool runs out partway through the hit
and the flat ratio would overshoot. So 50 means 50, armored or not.

## Backstabs and perk plugins

Two more places the cap was leaking.

The engine's backstab bonus is applied inside the damage pipeline, so a single
`OnTakeDamage` hook can be overwritten downstream. This version also hooks
`OnTakeDamageAlive`, which is the last editable player-damage path, and applies the configured
health cap there directly. Armor compensation belongs only in the earlier hook: doing it twice
turns a 50-health cap into 58 damage.

Third-party perk plugins that add knife damage run in the same pipeline. Capping at the end
means they cannot push a stab back over the limit.

## Both teams get capped, only CTs get a cooldown

Upstream only touched CT stabbing T. A T with a knife could still one-shot a CT. Now any
opposing-team knife hit is capped in either direction. The cooldown is still CT versus T only,
since that is the HNS mechanic and there is no reason to give a CT post-stab immunity.

## The cooldown blocked everything, not just knives

Upstream checked the cooldown timers before it checked whether the hit was even a knife:

```sourcepawn
if(g_bTimer[victim] != INVALID_HANDLE || g_bTimer2[attacker] != INVALID_HANDLE)
    return Plugin_Handled;
```

So a T on post-stab protection was immune to fall damage, fire, nades and everything else for
the whole cooldown. Now the knife and team check runs first, and only opposing knife hits get
blocked.

## Timers keyed by user id

Upstream passed the client index to `CreateTimer`. If that player disconnected and someone
else took the slot, the timer fired against the wrong person and cleared their render color.
Timers carry a user id now and check `g_bTimer[victim] != timer` before acting, so a stale
timer from a previous life does nothing.

Cooldowns are also cleared on round end, on map start, and when you set
`hns_f_knife_cooldown` or `hns_f_ct_cooldown` to 0. Upstream left running timers alive, so
disabling the feature still blocked stabs for up to a full cooldown afterwards.

## Announcements come from the engine, not the damage hook

Upstream announced the stab from inside `OnTakeDamage`, which means it announced hits that
another plugin then blocked. This version listens to `player_hurt` and `player_death` instead,
so it only prints stabs and kills that actually landed. Death events handle the lethal case
and `player_hurt` handles the rest, with a 0.2s guard so a multi-hit does not spam.

## Chat with no notification tick

The client plays the `HudChat.Message` sound for any SayText2 with its chat flag set, and both
`PrintToChat` and colors.inc's `CSayText2` set it. On a busy HNS server that is a constant
ticking. Every message here goes out through a SayText2 with the flag cleared, so the text
still lands in chat silently.

Player names are sanitized before they go in, since `{`, `}` and raw color bytes in a name
would otherwise be interpreted as formatting.

## OVA support

hidenseek's One Versus All mode passes the T role to whoever lands the stab, and that new T
has to be immediately killable. So while OVA is running, no post-stab protection is granted.
Damage is still capped. This reads an optional `HNS_IsOvaActive` native, so the plugin loads
fine without hidenseek.

## Convars

| Convar | Default | What |
|---|---|---|
| `hns_f_enable_plugin` | 1 | On or off. |
| `hns_f_knife_damage` | 50.0 | Health damage per opposing knife hit, backstabs and armor included. Capped at 50. |
| `hns_f_knife_cooldown` | 5.0 | Seconds of cooldown after a CT stabs a T. 0 disables. |
| `hns_f_ct_cooldown` | 1 | 0 off, 1 stabbed T gets protection, 2 both T and attacker are on cooldown. |
| `hns_f_enable_transparent` | 0 | Recolor the protected player during cooldown. |
| `hns_f_transparent` | 120 | Alpha for that effect. 255 is opaque. |
| `hns_f_color_r` / `_g` / `_b` | 255 / 0 / 0 | Color channels for it. |
| `hns_f_notify` | 1 | Cooldown messages. 0 off, 1 attacker, 2 victim, 3 both. |
| `hns_f_notify_annoc` | 1 | Announce stabs and kills in chat. |

The upstream damage convar had no upper bound and the announce convar had a mode 2 that
appended remaining HP. Both are gone: the cap is meaningless above 50 in HNS, and printing
someone's exact HP tells the CT whether one more stab finishes them.

## Credits

Original **HNS Anti Frag** by **Gold KingZ (oqyh)**:
[github.com/oqyh/HNS-Anti-Frag](https://github.com/oqyh/HNS-Anti-Frag)

## License

GPL-3.0, see `LICENSE`.
