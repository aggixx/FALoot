-- Define addon object
FALoot = {};
local A = FALoot;

--[[ =======================================================
     "Object" Definition
     ======================================================= --]]

--[[
   Define addon events functions
   
   A single unique event may have several methods called when it is triggered. These methods
   cannot be unregistered once registered.
--]]
A.events = {};
local E = A.events;
E.list = {};

E.Register = function(event, func)
  if type(event) ~= "string" then
    error("events.Register passed a non-string value for event");
    return;
  elseif type(func) ~= "function" then
    error("events.Register passed a non-function value for func");
    return;
  end
  if not E.list[event] then
    E.list[event] = {};
  end
  table.insert(E.list[event], func);
end

E.Trigger = function(event, ...)
  if E.list[event] then
    for i=1,#E.list[event] do
      E.list[event][i](...);
    end
  end
end

--[[
   Define messages, events subfunction

   Each unique message type may be set to have exactly one methods called when it is triggered.
   A method can be unregistered by calling the Unregister() method on the event.
-]]
A.messages = {};
local M = A.messages;
M.list = {};

M.Register = function(event, func)
  if type(event) ~= "string" then
    error("messages.Register passed a non-string value for event");
    return;
  elseif type(func) ~= "function" then
    error("messages.Register passed a non-function value for func");
    return;
  end
  M.list[event] = func;
end

M.Unregister = function(event)
  M.list[event] = nil;
end

M.Trigger = function(mEvent, msg, channel, source, ...)
  if M.list[mEvent] then
    M.list[mEvent](msg, channel, source, ...);
  end
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









