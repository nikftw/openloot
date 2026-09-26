# OpenLoot

Loot council addon for WoW Forever. Raiders vote with BIS, Upgrade, Offspec, or Pass. Officers award from a council screen. History is kept per loot session.

## Install

Copy the `openloot` folder into the Forever client's `Interface/AddOns` directory, then enable OpenLoot at the character screen. The folder name must stay `openloot`.

Reference copies of other loot addons, if you keep any beside this folder, are not part of OpenLoot.

The TOC targets interface `120100` (the 12.1 mainline API Forever shares). Forever beta builds that expect interface `16001` can change that line in `openloot/openloot.toc`, or load out-of-date addons while testing.

## Commands

- `/openloot` status
- `/openloot on` and `/openloot off` for the raid leader
- `/openloot run` start a session from the raid leader's bags
- `/openloot h` history
- `/openloot council` list current council
- `/openloot council rank <n>` council is guild rank index 0 through n
- `/openloot council chat` council is anyone who can speak in officer chat

## Raid mode

When a council member who is raid leader enters a raid, OpenLoot asks whether to run for that raid. Accepting turns Pass on Loot on for everyone else and makes the raid leader automatically need on group loot. A player who joins later asks the raid leader and turns Pass on Loot on only if this raid is set to OpenLoot.
