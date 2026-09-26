# OpenLoot

Raid loot council for WoW, version 0.3.0. It stays idle outside a raid. Inside one, raiders respond and anyone who can see officer chat awards.

## Install

Copy `openloot` into `Interface/AddOns`. The folder name stays `openloot`.

## Commands

`/ol` is the same as `/openloot`.

- `/openloot run` scan the leader's bags and start a session
- `/openloot trade` items still owed by the loot holder
- `/openloot v` who is current, outdated, or missing the addon. `version` is the same
- `/openloot h` award history. `history` is the same
- `/openloot resize` show or hide the window resize handles
- `/openloot demo` local sample screens. `/openloot demo off` clears them

`/openloot` on its own prints that list.

Delete `Dev.lua` and its line in `openloot.toc` before a public release. Demo data stays on screen only and is not written into saved loot.

## Raid

Entering a raid instance, or reloading there, asks once if you are the raid leader and you can see officer chat. Yes makes you the runner: Pass on Loot stays off and your rolls auto-need. Everyone else turns Pass on Loot on. That restores when OpenLoot turns off, you leave the group, or you leave the raid.

## Session

`/openloot run` only works inside a raid instance, and only for the runner. It sends rare-or-better unbound items, and soulbound items that are still tradeable, from the leader's bags. There is no item cap.

Everyone in the raid gets the session, in or out of the instance. They answer BIS, Upgrade, Offspec, or Pass, with an optional note. People in the raid who can see officer chat also get the council window. Assist does not. Award, Skip, and Disenchant apply immediately. The raid leader closing the council window ends the session for everyone. Other close buttons only hide that window.

A reload or a zone change keeps the open session, the votes already cast, and whichever windows were left open. Leaving the group clears it. A new session replaces the current one only after you confirm.

The loot holder gets a trade list. Opening a trade with someone who is owed loot puts in up to 6 items. Trade again for the rest.

Anyone who sees an award, skip, or disenchant keeps it in `/openloot h`. History opens on the latest session. Window positions, sizes, and opacity are remembered.
