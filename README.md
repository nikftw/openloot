# OpenLoot

Raid loot council addon for WoW Forever. Minimal memory and event footprint, anyone in the raid who can see officer chat handles council/awards.

Copy the `openloot` folder into `Interface/AddOns`. The folder name stays `openloot`. `/ol` is `/openloot`.

- `/ol run` start a loot session, raid leader only. Asks every raider for rare-or-better unbound items, and soulbound items that can still be traded.
- `/ol mule {name}` that character auto-needs. `/ol mule` clears it and the leader needs again. Works on group or master loot, when leader is masterloot or not.
- `/ol trade` items still in your bags that were awarded to someone else.
- `/ol v` who is current, outdated, or missing the addon.
- `/ol h` award history, latest session first, export if needed.
- `/ol resize` show or hide the window resize handles.

Entering a raid, or reloading there, asks once if you are the raid leader and can see officer chat. Yes makes you the runner. Pass on Loot stays off and rolls auto-need, unless a pack mule is set. Then only the mule needs, and everyone else passes, including you. Leaving the raid, or the mule leaving the group, puts that back on the leader.

On master loot, whoever has master loot gives each item to the mule, or to the leader if no mule is set.

Responses are BIS, Upgrade, Offspec, or Pass, plus an optional note. Officer chat gets the council window. Award, Skip, and Disenchant apply immediately. The raid leader closing the council window ends the session. Other close buttons only hide that window.

The person who has an awarded item is the one who trades it. A reload or zone change keeps the session. Leaving the group clears it. Replacing a session asks first. Window positions, sizes, and opacity are remembered.
