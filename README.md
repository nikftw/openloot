# OpenLoot

Raid loot council addon for WoW Forever. Minimal memory and event footprint, anyone in the raid who can see officer chat handles council/awards.

Copy the `openloot` folder into `Interface/AddOns`. The folder name stays `openloot`. `/ol` is `/openloot`.

- `/ol run` start a loot session, raid leader only. Asks every raider for rare-or-better unbound items, and soulbound items that can still be traded.
- `/ol mule {name}` that character takes the loot. `/ol mule` clears it and the leader takes it again.
- `/ol trade` items still in your bags that were awarded to someone else.
- `/ol v` who is current, outdated, or missing the addon.
- `/ol h` award history, latest session first, export if needed.
- `/ol resize` show or hide the window resize handles.

Entering a raid, or reloading there, asks once if you are the raid leader and can see officer chat. Yes makes you the runner. The collector is the pack mule, or the raid leader when no mule is set.

| Loot method | No mule | Mule set |
| --- | --- | --- |
| Group loot | Leader has Pass on Loot off and needs every roll. Everyone else passes. | Mule has Pass on Loot off and needs every roll. Everyone else passes, the leader too. |
| Master loot | The leader loots a boss and every item goes straight into the leader's bags. | The leader loots a boss and every item goes straight to the mule. |

Master loot hands items out with no prompt and no chat line. Only the raid leader can be master looter. The mule leaving the group puts the loot back on the leader. Leaving the group turns OpenLoot off and restores Pass on Loot. Zoning in and out, or dying and running back, changes nothing.

During the raid the addon sends nothing. The leader tells the raid once when OpenLoot is turned on or the mule changes. Anyone else with the addon asks the leader once, by whisper, after logging in, reloading, or joining a raid group, and the answer sets their Pass on Loot. A party never asks; a party converted to a raid asks then. A session starts with `/ol run`, which is the only time raiders are asked for their bags.

Responses are BIS, Upgrade, Offspec, or Pass, plus an optional note. Officer chat gets the council window. Other raiders' responses and the council's votes are kept only by officers. Award, Skip, and Disenchant apply immediately. The raid leader closing the council window ends the session. Other close buttons only hide that window.

The person who has an awarded item is the one who trades it. A reload or zone change keeps the session. Leaving the group clears it. Replacing a session asks first. Window positions, sizes, and opacity are remembered.

## Events

The collector is the pack mule, or the raid leader when no mule is set. Outside a raid, only the always-on rows are listening.

| Event | Listening | Does |
| --- | --- | --- |
| `ADDON_LOADED` | Load, then off | Starts the addon |
| `PLAYER_ENTERING_WORLD` | Login or reload, then off | Wakes inside a raid, stays idle everywhere else |
| `ZONE_CHANGED_NEW_AREA` | Always | Wakes or sleeps when you change zone |
| `GROUP_ROSTER_UPDATE` | Always | Runner only. If the pack mule leaves, the leader takes the loot again |
| `GROUP_LEFT` | Always | Clears the session and restores Pass on Loot. A party does the same, and does nothing if OpenLoot was never on |
| `CHAT_MSG_ADDON` | Always | OpenLoot messages only |
| `START_LOOT_ROLL` | Collector, in the raid | Auto-need |
| `CONFIRM_LOOT_ROLL` | Collector, in the raid | Hides the need confirm |
| `LOOT_READY` | Raid leader, in the raid | On master loot, gives each item to the mule, or the leader |
| `CONFIRM_LOOT_DISTRIBUTION` | Raid leader, in the raid | Hides the master loot confirm |
| `TRADE_SHOW` | You still owe a trade | Puts those items in the window |
| `TRADE_ACCEPT_UPDATE` | You still owe a trade | Notes what you put in |
| `TRADE_CLOSED` | You still owe a trade | Stops watching that trade |
| `UI_INFO_MESSAGE` | Trade window is open | Drops the row when the trade completes |
