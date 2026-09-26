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
- `/openloot trade` show the trades still owed by the loot holder
- `/openloot v` version check for the group
- `/openloot dev` starts a test session from every item in your bags and sends it as loot. `/openloot dev off` clears it. Remove `Dev.lua` before a real release.
- `/openloot demo` opens local sample screens for the raider, council, trades, history, and versions. `/openloot demo off` clears them.
- `/openloot h` history

## Raid mode

OpenLoot stays idle outside a raid instance. It wakes up only when the zone is a raid. Zoning in, or reloading there, asks the raid leader once whether OpenLoot is on. `/openloot run` rebuilds the council from guild members who are online and can speak in officer chat, then starts the loot session. The runner still needs on loot rolls during the fight.

## Trades

Awarding an item to someone else puts it on the loot holder's trade list. Opening a trade with that winner adds the item to the trade window. `/openloot trade` shows the list again.

## Versions

Clients announce their version in the group. `/openloot v` lists who is current, out of date, or missing the addon. Turning a raid on runs the same check.
