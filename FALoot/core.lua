-- Define addon object
FALoot = {};
local A = FALoot;

--[[ =======================================================
     "Object" Definition
     ======================================================= --]]

-- Define addon events functions
A.events = {};
local E = A.events;
E.list = {};

E.Register = function(event, func)
  if type(event) ~= "string" then
    error("events.Register passed a non-string value for event");
    return;
  end
  E.list[event] = func;
end

E.Trigger = function(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
  if E.list[event] then
    E.list[event](arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
  end
end

-- Define messages, events subfunction
A.messages = {};
local M = A.messages;
M.list = {};

M.Register = function(event, func)
  if type(event) ~= "string" then
    error("events.Register passed a non-string value for event");
    return;
  end
  M.list[event] = func;
end

--[[
  Trigger is handled by appropriate WoW API chat events.
--]]

-- Define session data
A.sData = {};
local SD = A.sData;

-- Define persistent data
A.pData = {};
local PD = A.pData;

-- Define options
PD.options = {};
local O = PD.options;

-- Define functions
A.functions = {};
local F = A.functions;

A.UI = {};

--[[ =======================================================
     Addon Definition & Properties
     ======================================================= --]]
 
A.NAME = "FALoot";
A.MVERSION = 7; -- Addons only communicate with users of the same major version.
A.REVISION = 1; -- Specific code revision for identification purposes.

A.stub = LibStub("AceAddon-3.0"):NewAddon(A.NAME);
LibStub("AceComm-3.0"):Embed(A.stub);

A.COLOR = "FFF9CC30";
A.CHAT_HEADER  = "|c" .. A.COLOR .. "FA Loot:|r ";
A.MSG_PREFIX = "FALoot";
A.DOWNLOAD_URL = "https://github.com/aggixx/FALoot";









