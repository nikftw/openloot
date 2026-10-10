-- A full 20-player raid night, in virtual time with the addon message throttle.
-- Shane (leader) holds 20 drops and Veyra (officer) holds 5 that were given to
-- her. Every raider responds, three officers vote and award, and both holders
-- trade everything out.  Run with: node run.js raid
local sim = ...
local log, shortOf, roster, catalog, clients = sim.log, sim.shortOf, sim.roster, sim.catalog, sim.clients
local advance, clock, wireStats = sim.advance, sim.clock, sim.wireStats

local problems = 0
local function check(ok, text)
	if not ok then
		problems = problems + 1
		log("PROBLEM " .. text)
	end
end

local function step(label, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		problems = problems + 1
		log("PROBLEM " .. label .. "\n" .. tostring(err))
	end
end

local mark = { frames = 0, bytes = 0, at = 0 }
local function report(label)
	log(string.format("%-34s %4d messages %7d bytes  %5.1fs   (throttled sends: %d)",
		label, wireStats.frames - mark.frames, wireStats.bytes - mark.bytes, clock.now - mark.at, wireStats.throttled or 0))
	mark = { frames = wireStats.frames, bytes = wireStats.bytes, at = clock.now }
end

-- Advance until fn() is true, in 0.1s steps. Returns the seconds it took.
local function waitFor(limit, fn)
	local start = clock.now
	while clock.now - start < limit do
		if fn() then
			return clock.now - start
		end
		advance(0.1)
	end
	return fn() and (clock.now - start) or nil
end

-- Items. Extra slots so classes have different things to want.
local more = {
	{ 30001, "Crown of the Fallen", "INVTYPE_HEAD", 4, 4, 134000 },
	{ 30002, "Mantle of Ash", "INVTYPE_SHOULDER", 4, 1, 134001 },
	{ 30003, "Gloves of Haste", "INVTYPE_HAND", 4, 2, 134002 },
	{ 30004, "Girdle of Embers", "INVTYPE_WAIST", 4, 3, 134003 },
	{ 30005, "Legplates of Wrath", "INVTYPE_LEGS", 4, 4, 134004 },
	{ 30006, "Treads of Fire", "INVTYPE_FEET", 4, 2, 134005 },
	{ 30007, "Bracers of Might", "INVTYPE_WRIST", 4, 4, 134006 },
	{ 30008, "Choker of Flame", "INVTYPE_NECK", 4, 0, 134007 },
	{ 30009, "Idol of Embers", "INVTYPE_TRINKET", 4, 0, 134008 },
	{ 30010, "Staff of Dominance", "INVTYPE_2HWEAPON", 2, 10, 134009 },
	{ 30011, "Green Bracers", "INVTYPE_WRIST", 4, 1, 134010, 2 },
	{ 30012, "Soulbound Cloak", "INVTYPE_CLOAK", 4, 1, 134011 },
}
for _, def in ipairs(more) do
	sim.addItem({ id = def[1], name = def[2], equip = def[3], classID = def[4], subClassID = def[5], icon = def[6], ilvl = 70, quality = def[7] or 4 })
end

-- Roster: Shane leads, Veyra, Nyx and Kael are officers (see officer chat).
for index = #roster, 1, -1 do
	roster[index] = nil
end
local classes = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "SHAMAN", "WARLOCK", "PALADIN", "MONK", "DEATHKNIGHT", "EVOKER", "DEMONHUNTER" }
local names = { "Shane", "Veyra", "Nyx", "Kael", "Thorn", "Brin", "Corra", "Dask", "Elow", "Fenn", "Gria", "Hollis", "Ivo", "Jessa", "Kirr", "Lom", "Mira", "Nole", "Orrin", "Pell" }
for index, name in ipairs(names) do
	roster[index] = {
		name = name .. "-Area52",
		class = classes[(index - 1) % #classes + 1],
		raidRank = index == 1 and 2 or 0,
		guildRank = index == 1 and 0 or (index <= 4 and 1 or 4),
		guildRankName = index == 1 and "Guild Master" or (index <= 4 and "Officer" or "Raider"),
		note = index % 5 == 0 and "Clone1" or "Main",
	}
end

-- Bags. Shane: 20 drops, plus two that must not be offered (a green, and a
-- soulbound cloak past its trade window). Veyra: 5 drops given to her, still
-- inside their trade window.
local drops = { 19019, 17182, 19888, 18821, 17063, 18813, 19378, 30001, 30002, 30003, 30004, 30005, 30006, 30007, 30008, 30009, 30010 }
local shaneBag = {}
for index = 1, 20 do
	shaneBag[#shaneBag + 1] = { id = drops[(index - 1) % #drops + 1], bound = index % 4 == 0, tradeable = index % 4 == 0 }
end
shaneBag[#shaneBag + 1] = { id = 30011, bound = false }
shaneBag[#shaneBag + 1] = { id = 30012, bound = true, tradeable = false }
local veyraBag = {}
for index = 1, 5 do
	veyraBag[index] = { id = drops[(index * 3) % #drops + 1], bound = true, tradeable = true }
end
for _, person in ipairs(roster) do
	sim.bagsByPlayer[person.name] = { [0] = {} }
end
sim.bagsByPlayer["Shane-Area52"] = { [0] = shaneBag }
sim.bagsByPlayer["Veyra-Area52"] = { [0] = veyraBag }

local function client(name)
	for _, entry in ipairs(clients) do
		if shortOf(entry.spec.name) == name then
			return entry.env
		end
	end
end

local function countBag(name)
	local count = 0
	for _, item in ipairs(sim.bagsByPlayer[name .. "-Area52"][0]) do
		if item then
			count = count + 1
		end
	end
	return count
end

local function listens(env, event)
	for frame in pairs(env._eventFrames or {}) do
		if frame._events and frame._events[event] then
			return true
		end
	end
	return false
end

local function passing(name)
	return client(name).GetOptOutOfLoot()
end

-- Count what a client prints to chat, to prove master loot stays silent.
local printed = {}
local function watchPrints(name)
	local env = client(name)
	local original = env.print
	printed[name] = 0
	env.print = function(text)
		printed[name] = printed[name] + 1
		original(text)
	end
end

-- Every client sees a group-loot roll; returns who rolled Need.
local nextRoll = 100
local function groupLootDrop()
	nextRoll = nextRoll + 1
	local needed = {}
	for _, entry in ipairs(clients) do
		entry.env._rolled = nil
		entry.env.fire("START_LOOT_ROLL", nextRoll, 60)
		if entry.env._rolled == 1 then
			needed[#needed + 1] = shortOf(entry.spec.name)
		end
	end
	return table.concat(needed, ",")
end

-- The leader loots a boss with three items under master loot.
local function masterLootBoss()
	sim.lootSim.method = "master"
	sim.lootSim.items = 3
	sim.lootSim.given = {}
	sim.lootSim.candidates = {}
	for index, person in ipairs(roster) do
		sim.lootSim.candidates[index] = shortOf(person.name)
	end
	client("Shane").OpenLoot.RaidMode.lastMaster = nil
	for _, entry in ipairs(clients) do
		entry.env.fire("LOOT_READY", false)
	end
	local to = {}
	for _, gift in ipairs(sim.lootSim.given) do
		to[#to + 1] = tostring(gift.from) .. ">" .. tostring(gift.to)
	end
	sim.lootSim.method = "group"
	return table.concat(to, ",")
end

local function checkRoles(collector, label)
	for _, entry in ipairs(clients) do
		local who = shortOf(entry.spec.name)
		local want = who ~= collector
		check(passing(who) == want, label .. ": " .. who .. " has Pass on Loot " .. (passing(who) and "on" or "off"))
		check(listens(entry.env, "START_LOOT_ROLL") == (who == collector), label .. ": " .. who .. " roll listening is wrong")
		check(listens(entry.env, "LOOT_READY") == (who == "Shane"), label .. ": " .. who .. " master loot listening is wrong")
	end
end

clock.virtual = true
print("Raid night: 20 players, Shane leads. Virtual time; each client may send " ..
	"10 addon messages at once, then 1 more per second.")
print("")

for _, person in ipairs(roster) do
	sim.boot(person.name)
end
local shane = client("Shane")

-- Instrumentation: how often each client redraws, receives and rescans.
local work = {}
local function count(name, key)
	work[name] = work[name] or {}
	work[name][key] = (work[name][key] or 0) + 1
end
for _, entry in ipairs(clients) do
	local who = shortOf(entry.spec.name)
	local OL = entry.env.OpenLoot
	local function wrap(owner, method, key, shownOnly)
		local original = owner[method]
		owner[method] = function(self, ...)
			count(who, key .. " calls")
			if not shownOnly or (self.frame and self.frame:IsShown()) then
				count(who, key .. " redraws")
			end
			return original(self, ...)
		end
	end
	wrap(OL.RaiderFrame, "Refresh", "raider window", true)
	wrap(OL.CouncilFrame, "Refresh", "council window", true)
	wrap(OL.Council, "Rebuild", "guild roster scan")
	wrap(OL.Comms, "OnMessage", "frames received")
	for _, api in ipairs({ "Ambiguate", "GetRaidRosterInfo", "GetGuildRosterInfo", "GetNumGuildMembers" }) do
		local original = entry.env[api]
		entry.env[api] = function(...)
			count(who, api)
			return original(...)
		end
	end
end

advance(5)
report("Everyone logs in")

step("Shane says yes to running OpenLoot", function()
	check(sim.click(shane, "Yes"), "the run prompt did not appear for Shane")
end)
advance(5)
report("OpenLoot turned on for the raid")
checkRoles("Shane", "no mule")

-- Bosses ----------------------------------------------------------------------
watchPrints("Shane")
local needed
step("group loot, no mule", function() needed = groupLootDrop() end)
check(needed == "Shane", "group loot without a mule: Need from " .. needed .. ", expected Shane")
step("master loot, no mule", function()
	local given = masterLootBoss()
	check(given == "Shane>Shane,Shane>Shane,Shane>Shane", "master loot without a mule went " .. given)
end)
advance(5)
report("Two bosses, no mule")

step("/ol mule Veyra", function() shane.OpenLoot:Slash("mule Veyra") end)
advance(2)
report("Shane sets Veyra as the mule")
checkRoles("Veyra", "mule Veyra")

printed.Shane = 0
step("group loot, mule", function() needed = groupLootDrop() end)
check(needed == "Veyra", "group loot with a mule: Need from " .. needed .. ", expected Veyra")
step("master loot, mule", function()
	local given = masterLootBoss()
	check(given == "Shane>Veyra,Shane>Veyra,Shane>Veyra", "master loot with a mule went " .. given)
end)
check(printed.Shane == 0, "Shane saw " .. printed.Shane .. " chat lines while bosses were looted")
advance(5)
report("Two bosses with the mule")

-- A wipe: everyone dies, releases, runs back in as a ghost.
step("wipe and run back", function()
	for _, entry in ipairs(clients) do
		entry.env._ghost = true
		entry.env._outside = true
		entry.env.fire("ZONE_CHANGED_NEW_AREA")
	end
	advance(30)
	for _, entry in ipairs(clients) do
		entry.env._outside = false
		entry.env.fire("ZONE_CHANGED_NEW_AREA")
		entry.env._ghost = false
	end
	advance(5)
end)
report("A wipe and run back")
checkRoles("Veyra", "after the wipe")

-- Joining, logging in and reloading: anyone with the addon gets Pass on
-- Loot from the leader, inside the instance or not. ---------------------------
-- A reload: memory goes, saved variables stay.
local function reload(name)
	local env = client(name)
	env.OpenLoot.Session.active = nil
	env.OpenLoot.RaidMode.needAsk = true
	env.OpenLoot.RaidMode.leader = nil
	env.OpenLoot:SyncPresence()
	advance(5)
end

local function leaveGroup(name)
	local env = client(name)
	env._solo = true
	env.fire("GROUP_LEFT")
	check(not passing(name), name .. " still has Pass on Loot on after leaving the group")
end

local function joinGroup(name)
	local env = client(name)
	env._solo = false
	env.fire("GROUP_ROSTER_UPDATE")
	advance(3)
end

step("Thorn is invited into a party, which is then made a raid", function()
	local env = client("Thorn")
	leaveGroup("Thorn")
	env._outside = true
	env.fire("ZONE_CHANGED_NEW_AREA")
	env._solo = false
	env._party = true
	local before = wireStats.frames
	env.fire("GROUP_ROSTER_UPDATE")
	advance(3)
	check(wireStats.frames == before, "Thorn asked the leader while only in a party")
	check(not passing("Thorn"), "Thorn got Pass on Loot while only in a party")
	env._party = false
	env.fire("GROUP_ROSTER_UPDATE")
	advance(3)
	check(passing("Thorn"), "Thorn did not get Pass on Loot when the party became a raid")
	env._outside = false
	env.fire("ZONE_CHANGED_NEW_AREA")
	advance(2)
end)
check(passing("Thorn"), "Thorn lost Pass on Loot on entering the instance")
report("Party, then converted to a raid")

step("Brin joins while still outside the instance", function()
	local env = client("Brin")
	leaveGroup("Brin")
	env._outside = true
	env.fire("ZONE_CHANGED_NEW_AREA")
	joinGroup("Brin")
	check(passing("Brin"), "Brin joined outside the instance without Pass on Loot")
	env._outside = false
	env.fire("ZONE_CHANGED_NEW_AREA")
	advance(2)
end)
check(passing("Brin"), "Brin lost Pass on Loot on entering the instance")
report("A raider joins outside, then enters")

step("Corra logs in before the group roster has loaded", function()
	local env = client("Corra")
	env._outside = true
	env.SetOptOutOfLoot(false)
	env.OpenLoot.db.activeRaid = nil
	env.OpenLoot.db.passTouch = nil
	env._solo = true
	reload("Corra")
	check(not passing("Corra"), "Corra was given Pass on Loot before being in a group")
	joinGroup("Corra")
	env._outside = false
	env.fire("ZONE_CHANGED_NEW_AREA")
	advance(2)
end)
check(passing("Corra"), "Corra logged in without getting Pass on Loot once the roster loaded")
report("A raider logs in before the roster loads")

step("Dask reloads outside the instance", function()
	local env = client("Dask")
	env.SetOptOutOfLoot(false)
	env.OpenLoot.db.activeRaid = nil
	env.OpenLoot.db.passTouch = nil
	env._outside = true
	reload("Dask")
	env._outside = false
	env.fire("ZONE_CHANGED_NEW_AREA")
	advance(2)
end)
check(passing("Dask"), "Dask reloaded outside without getting Pass on Loot")
report("A raider reloads outside the instance")
checkRoles("Veyra", "after joins and logins")

-- Session ----------------------------------------------------------------------
step("/ol run", function()
	shane.OpenLoot:Slash("run")
end)
local session
local took = waitFor(30, function()
	session = shane.OpenLoot.Session.active
	if not session then
		return false
	end
	for _, entry in ipairs(clients) do
		local active = entry.env.OpenLoot.Session.active
		if not active or active.id ~= session.id or #active.items ~= #session.items then
			return false
		end
	end
	return true
end)
check(session and #session.items == 25, "expected 25 items in the session, got " .. tostring(session and #session.items))
check(took ~= nil, "not every client had the full session within 30s")
report("/ol run: bag scan and session")
log(string.format("  every client had all %d items after %.1fs", session and #session.items or 0, took or -1))
local fromVeyra = 0
for _, item in ipairs(session and session.items or {}) do
	if item.holder == "Veyra" then
		fromVeyra = fromVeyra + 1
	end
	check(not item.link:find("Green Bracers", 1, true) and not item.link:find("Soulbound Cloak", 1, true),
		"an item that cannot be traded was offered: " .. item.link)
end
check(fromVeyra == 5, "expected 5 items held by Veyra, got " .. fromVeyra)

-- Responses: everyone works down the list, one click every 1-2 seconds -------
local responses = { "BIS", "UPGRADE", "OFFSPEC", "PASS" }
local nextItem = {}
local count = #session.items
local clicks = 0
local start = clock.now
while true do
	local anyLeft = false
	for position, entry in ipairs(clients) do
		local who = shortOf(entry.spec.name)
		local index = nextItem[who] or 1
		if index <= count then
			anyLeft = true
			if position % 2 == 1 or math.floor(clock.now - start) % 2 == 0 then
				local response = responses[(index * 7 + position * 3) % 4 + 1]
				local note = (index + position) % 6 == 0 and "for my offspec" or nil
				step(who .. " responds", function()
					entry.env.OpenLoot.Session:SetResponse(index, response, note)
				end)
				nextItem[who] = index + 1
				clicks = clicks + 1
			end
		end
	end
	if not anyLeft then
		break
	end
	advance(1)
end
local council = { "Shane", "Veyra", "Nyx", "Kael" }
local settle = waitFor(60, function()
	for _, name in ipairs(council) do
		for _, item in ipairs(client(name).OpenLoot.Session.active.items) do
			local seen = 0
			for _ in pairs(item.votes) do
				seen = seen + 1
			end
			if seen < #roster then
				return false
			end
		end
	end
	return true
end)
check(settle ~= nil, "the council did not see every response within 60s of the last click")
report(clicks .. " responses (" .. count .. " items x 20)")
log(string.format("  the last response reached every officer %.1fs after the last click", settle or -1))

-- Council: a couple of contested items get a vote; the rest is settled on Discord.
local contested = { 3, 11, 19 }
for _, name in ipairs(council) do
	local frame = client(name).OpenLoot.CouncilFrame
	check(frame.frame and frame.frame:IsShown(), name .. " does not see the council window")
	for _, index in ipairs(contested) do
		step(name .. " votes on item " .. index, function()
			frame.icons[index]._scripts.OnClick(frame.icons[index])
			local top = frame.rows[1]
			top.actions.vote._scripts.OnClick(top.actions.vote)
		end)
		advance(0.3)
	end
end
advance(3)
report("4 officers vote on 3 contested items")
for _, index in ipairs(contested) do
	for _, name in ipairs(council) do
		local ballots = 0
		for _ in pairs(client(name).OpenLoot.Session.active.items[index].ballots) do
			ballots = ballots + 1
		end
		check(ballots == 4, name .. " sees " .. ballots .. " council votes on item " .. index)
	end
end
for _, entry in ipairs(clients) do
	local who = shortOf(entry.spec.name)
	local isCouncil = false
	for _, name in ipairs(council) do
		isCouncil = isCouncil or name == who
	end
	if not isCouncil then
		local frame = entry.env.OpenLoot.CouncilFrame.frame
		check(not (frame and frame:IsShown()), who .. " can see the council window")
		for index, item in ipairs(entry.env.OpenLoot.Session.active.items) do
			check(next(item.ballots) == nil, who .. " is holding council votes for item " .. index)
			for voter in pairs(item.votes) do
				check(voter == who, who .. " is holding " .. voter .. "'s response to item " .. index)
			end
		end
	end
end

-- Awards: split between three officers, each clicking Award on the top row --
local awarders = { "Shane", "Veyra", "Nyx" }
local expected = {}
for index = 1, count do
	local name = awarders[(index - 1) % #awarders + 1]
	local frame = client(name).OpenLoot.CouncilFrame
	step(name .. " awards item " .. index, function()
		frame.icons[index]._scripts.OnClick(frame.icons[index])
		local top = frame.rows[1]
		expected[index] = top.short
		top.actions.award._scripts.OnClick(top.actions.award)
	end)
	advance(2)
end
advance(5)
report("3 officers award 25 items")
for _, entry in ipairs(clients) do
	local who = shortOf(entry.spec.name)
	local active = entry.env.OpenLoot.Session.active
	local history = entry.env.OpenLoot.db.history.sessions[session.id]
	for index = 1, count do
		local item = active and active.items[index]
		check(item and item.awardedTo == expected[index],
			who .. " shows item " .. index .. " awarded to " .. tostring(item and item.awardedTo) .. ", expected " .. tostring(expected[index]))
	end
	check(history and #history.awards == count, who .. " has " .. tostring(history and #history.awards) .. " awards in history")
	check(history and history.instance == "Molten Core" and history.mapID == 409, who .. " history does not name the raid")
	for _, award in ipairs(history and history.awards or {}) do
		check(award.class ~= "", who .. " history has no class for " .. tostring(award.winner))
	end
end

-- Trades ----------------------------------------------------------------------
local function owed(env)
	return env.OpenLoot.Trade.list
end

local function setupTrading(env)
	env.ClearCursor = function() end
	env.ERR_TRADE_COMPLETE = "Trade complete."
	env.LE_GAME_ERR_TRADE_COMPLETE = 1
	env._recipient = env.CreateFrame("FontString", "TradeFrameRecipientNameText")
	function env.C_Container.PickupContainerItem(bag, slot)
		env._cursor = { bag = bag, slot = slot }
		return true
	end
	function env.ClickTradeButton(slot)
		env._tradeSlots[slot] = env._cursor
		env._cursor = nil
		return true
	end
	function env.GetTradePlayerItemLink(slot)
		local placed = env._tradeSlots[slot]
		return placed and env.C_Container.GetContainerItemLink(placed.bag, placed.slot) or nil
	end
end

-- One trade window between holder and winner: the addon fills it, both
-- accept, and the items move bags.
local function trade(holderName, winnerName)
	local env = client(holderName)
	env._tradeSlots = {}
	env._recipient:SetText(winnerName)
	env.fire("TRADE_SHOW")
	advance(1)
	env.fire("TRADE_ACCEPT_UPDATE", 1, 1)
	local moved = 0
	local holderBag = sim.bagsByPlayer[holderName .. "-Area52"][0]
	local winnerBag = sim.bagsByPlayer[winnerName .. "-Area52"][0]
	for slot = 1, 6 do
		local placed = env._tradeSlots[slot]
		if placed then
			winnerBag[#winnerBag + 1] = { id = holderBag[placed.slot].id, bound = false }
			holderBag[placed.slot] = false
			moved = moved + 1
		end
	end
	env.fire("UI_INFO_MESSAGE", 1, "Trade complete.")
	env.fire("TRADE_CLOSED")
	advance(2)
	return moved
end

local before = {}
for _, person in ipairs(roster) do
	before[shortOf(person.name)] = countBag(shortOf(person.name))
end
local traded = { Shane = 0, Veyra = 0 }
for _, holder in ipairs({ "Shane", "Veyra" }) do
	local env = client(holder)
	setupTrading(env)
	local shouldOwe = 0
	for index, item in ipairs(session.items) do
		if item.holder == holder and expected[index] ~= holder then
			shouldOwe = shouldOwe + 1
		end
	end
	check(#owed(env) == shouldOwe, holder .. " owes " .. #owed(env) .. " trades, expected " .. shouldOwe)
	local guard = 0
	while #owed(env) > 0 and guard < 40 do
		guard = guard + 1
		local winner = owed(env)[1].winner
		local moved = 0
		step(holder .. " trades " .. winner, function()
			moved = trade(holder, winner)
		end)
		traded[holder] = traded[holder] + moved
		if moved == 0 then
			check(false, holder .. " could not place anything for " .. winner)
			break
		end
	end
	check(#owed(env) == 0, holder .. " still owes " .. #owed(env) .. " trades")
end
report("Holders trade everything out")
log(string.format("  Shane handed over %d items, Veyra %d", traded.Shane, traded.Veyra))
for index, item in ipairs(session.items) do
	local winner = expected[index]
	if winner and winner ~= item.holder then
		before[winner] = before[winner] + 1
	end
end
for _, person in ipairs(roster) do
	local who = shortOf(person.name)
	local want = before[who]
	if who == "Shane" or who == "Veyra" then
		want = countBag(who)
	end
	check(countBag(who) == want, who .. " has " .. countBag(who) .. " items in bags, expected " .. want)
end

-- Reloads ----------------------------------------------------------------------
step("Thorn reloads", function() reload("Thorn") end)
report("A raider reloads")
step("Kael reloads", function() reload("Kael") end)
report("An officer reloads")
step("Shane reloads", function() reload("Shane") end)
report("The leader reloads")
checkRoles("Veyra", "after the reloads")

-- Where the work went ---------------------------------------------------------
print("")
log("Traffic by op (count, bytes, deliveries = count x receivers):")
local ops = {}
for op, entry in pairs(wireStats.ops) do
	ops[#ops + 1] = { op = op, entry = entry }
end
table.sort(ops, function(a, b) return a.entry.bytes > b.entry.bytes end)
for _, row in ipairs(ops) do
	local e = row.entry
	log(string.format("  %-6s %5d msgs %7d bytes  avg %3d  deliveries %6d  e.g. %s", row.op, e.count, e.bytes,
		math.floor(e.bytes / e.count + 0.5), e.receivers, (e.sample:gsub("[]", "|"):gsub("[]", "^")):sub(1, 90)))
end

print("")
log("Work per client (Shane = leader, Veyra = officer + holder, Thorn = raider):")
for _, who in ipairs({ "Shane", "Veyra", "Thorn" }) do
	local keys = {}
	for key in pairs(work[who] or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = key .. " " .. work[who][key]
	end
	log("  " .. who .. ": " .. table.concat(parts, ", "))
end

local function size(value, seen)
	seen = seen or {}
	if type(value) == "string" then
		return #value + 2
	elseif type(value) ~= "table" then
		return #tostring(value)
	end
	if seen[value] then
		return 0
	end
	seen[value] = true
	local total = 2
	for key, inner in pairs(value) do
		total = total + size(key, seen) + size(inner, seen) + 2
	end
	return total
end
print("")
log("Saved variables per client, roughly (bytes):")
for _, who in ipairs({ "Shane", "Veyra", "Thorn" }) do
	local db = client(who).OpenLoot.db
	local parts = {}
	for _, key in ipairs({ "history", "session", "scan", "trades", "frames", "windows", "activeRaid" }) do
		if db[key] then
			parts[#parts + 1] = key .. " " .. size(db[key])
		end
	end
	log("  " .. who .. ": " .. table.concat(parts, ", "))
end
log("Timers scheduled across all clients: " .. clock.seq)

print("")
log(string.format("Total: %d addon messages, %d bytes, %.0fs of raid time, %d sends held back by the throttle.",
	wireStats.frames, wireStats.bytes, clock.now, wireStats.throttled or 0))
log(problems == 0 and "All checks passed." or (problems .. " problems."))
