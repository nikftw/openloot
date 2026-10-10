"use strict";

const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib } = fengari;

const files = [
	"Core.lua", "Comms.lua", "Council.lua", "Items.lua", "UI.lua", "RaidMode.lua",
	"Session.lua", "RaiderFrame.lua", "CouncilFrame.lua", "History.lua", "Trade.lua", "Version.lua",
];

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const name of files) {
	const source = fs.readFileSync(path.join(__dirname, "..", "openloot", name), "utf8");
	lua.lua_pushstring(L, fengari.to_luastring(name));
	lua.lua_pushstring(L, fengari.to_luastring(source));
	lua.lua_settable(L, -3);
}
lua.lua_setglobal(L, fengari.to_luastring("SOURCES"));
// `node run.js raid` runs raid.lua on top of the sim instead of the default demo.
const scenario = process.argv[2];
if (scenario) {
	const source = fs.readFileSync(path.join(__dirname, scenario + ".lua"), "utf8");
	lua.lua_pushstring(L, fengari.to_luastring(source));
	lua.lua_setglobal(L, fengari.to_luastring("SCENARIO_SOURCE"));
	lua.lua_pushstring(L, fengari.to_luastring(scenario + ".lua"));
	lua.lua_setglobal(L, fengari.to_luastring("SCENARIO_NAME"));
}
const file = path.join(__dirname, "harness.lua");
const status = lauxlib.luaL_dofile(L, fengari.to_luastring(file));
if (status !== lua.LUA_OK) {
	const raw = lua.lua_tolstring(L, -1, null);
	console.error(fengari.to_jsstring(raw));
	process.exit(1);
}
