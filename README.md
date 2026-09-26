# OpenLoot

Raid loot council for WoW 0.3.0. Idle outside a raid. Raiders respond. Anyone in the raid who can see officer chat awards.

Copy `openloot` into `Interface/AddOns`. The folder name stays `openloot`. `/ol` is `/openloot`, and alone it prints the commands.

- `/ol run` scan the leader's bags and start a session. Raid instance only, runner only. Rare-or-better unbound items, and soulbound items that are still tradeable. No item cap.
- `/ol trade` items the loot holder still owes. A trade puts in up to 6.
- `/ol v` who is current, outdated, or missing the addon. `version` is the same.
- `/ol h` award history, latest session first. `history` is the same.
- `/ol resize` show or hide the window resize handles.
- `/ol demo` local sample screens. `demo off` clears them. Demo is not saved.

Entering a raid instance, or reloading there, asks once if you are the raid leader and can see officer chat. Yes makes you the runner: Pass on Loot stays off and rolls auto-need. Everyone else turns Pass on Loot on until they leave the group or the raid.

The whole raid gets the session, in or out of the instance. Responses are BIS, Upgrade, Offspec, or Pass, plus an optional note. Officer chat gets the council window. Assist does not. Award, Skip, and Disenchant apply immediately. The raid leader closing the council window ends the session. Other close buttons only hide that window.

A reload or zone change keeps the session, votes, and open windows. Leaving the group clears it. Replacing a session asks first. Window positions, sizes, and opacity are remembered.
