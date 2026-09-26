# OpenLoot

Raid loot council. It stays idle outside a raid. Inside one, raiders respond and officers award.

## Install

Copy `openloot` into `Interface/AddOns`. The folder name stays `openloot`.

## Commands

- `/openloot` status
- `/openloot on` / `off`
- `/openloot run` scan the leader's bags and start
- `/openloot trade` items still owed by the loot holder
- `/openloot v` who is current, old, or missing the addon
- `/openloot h` award history for the selected session
- `/openloot dev` send every bag item as a test session. `dev off` clears it
- `/openloot demo` local sample screens. `demo off` clears them

Delete `Dev.lua` and its line in `openloot.toc` before a public release.

## Session

Entering a raid, or reloading there, asks the leader once. Yes makes them the runner: Pass on Loot stays off and their rolls auto-need. Everyone else turns Pass on Loot on. That restores when OpenLoot turns off, they leave the group, or they leave the raid.

`/openloot run` keeps guild members who are online and can speak in officer chat, then sends rare-or-better unbound or still-tradeable bag items to everyone in the raid, in or out of the zone. Anyone in the raid can respond. Officers also get the council window. The holder gets a trade list. Anyone who sees an award, skip, or disenchant keeps it in `/openloot h`. Window positions are remembered.
