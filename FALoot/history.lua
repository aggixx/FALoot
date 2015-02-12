local A = FALoot;
local U = A.util;
local PD = A.pData;
local SD = A.sData;
local F = A.functions
local AM = A.addonMessages;
local C = A.commands;

F.history = {};

PD.table_itemHistory = {};

SD.bonusIDDescriptors = {
  [450] = "Mythic",
  [561] = "WF",
  [562] = "WF",
  [564] = "Soc",
  [565] = "Soc",
  [566] = "Heroic",
  [567] = "Mythic",
}

local function makeId()
  local s = "" -- Start string
  for i = 1, 3 do
    s = s .. string.char(math.random(32, 126)) -- Generate random number from 32 to 126, turn it into character and add to string
  end
  return s -- Return string
end

F.history.createEntry = function(itemString, winner, bid)
  local id;
  repeat
    id = makeId();
    for i,v in pairs(PD.table_itemHistory) do
      if i == id then
        id = nil;
        break
      end
    end
  until id
  
  PD.table_itemHistory[id] = {
    ["itemString"] = itemString,
    ["winner"] = winner,
    ["value"] = bid,
  };
  
  F.sendMessage("GUILD", nil, true, "newHist", id, PD.table_itemHistory[id]);
  
  PD.table_itemHistory[id].date = time();
  
  local baseId = string.match(itemString, "^%d+");
  PD.tooltip_cache[baseId] = PD.tooltip_cache[baseId] or {};
  table.insert(PD.tooltip_cache[baseId], id);
end

AM.Register("newHist", function(channel, sender, id, data)
  if PD.table_itemHistory[id] then
    U.debug("Received item history data with an ID that already exists!", 1);
    return;
  end
  
  PD.table_itemHistory[id] = data;
  PD.table_itemHistory[id].date = PD.table_itemHistory[id].date or time();
  
  local baseId = string.match(data.itemString, "^%d+");
  PD.tooltip_cache[baseId] = PD.tooltip_cache[baseId] or {};
  table.insert(PD.tooltip_cache[baseId], id);
  
  if syncing then
    syncCount = syncCount + 1;
  end
end);

local syncing = false;
local syncCount = 0;

C.Register("history", function(arg)
  arg = string.lower(arg);
  if arg == "sync" or arg == "syncf" then
    if syncing then
      U.debug("Synchronization is already in progress! Please wait for the current sync to complete.")
      return;
    end
    local s = "";
    local t = time();
    for i,v in pairs(PD.table_itemHistory) do
      if arg == "syncf" or t-v.date < 30 * 24 * 60* 60 then
        s = s..i;
      end
    end
    
    if arg == "syncf" then
      F.sendMessage("RAID", nil, true, "histSyncF", s);
    else
      F.sendMessage("RAID", nil, true, "histSync", s);
    end
    
    syncing = true;
    syncCount = 0;
    
    U.debug("Synchronizing item history...");
    C_Timer.After(30, function()
      syncing = false;
      U.debug("Finished adding "..syncCount.." new item records.");
    end)
  else
    U.debug("Bad argument for /fa history, allowed arguments are:\n  /fa history sync\n  /fa history syncF");
  end
end, "sync -- Perform a synchronization of item history with others in the raid group.");

local function syncRespond(full, sender, data)
  data = data or "";

  -- deconstruct
  local t = {}
  for i=1,string.len(data)-2,3 do
    table.insert(t, string.sub(data, i, i+2));
  end
  
  U.debug(t, 4);
  
  local t = time();
  
  -- look for entries sender doesn't have
  for i,v in pairs(PD.table_itemHistory) do
    local found;
    
    if full or t-v.date < 30 * 24 * 60 * 60 then
      local found = false;
      for j=1,#t do
        if t[j] == i then
          found = true;
	  break
        end
      end
    end
    
    if found == false then
      U.debug('Sending entry "'..i..'" to '..sender..".", 2)
      F.sendMessage("WHISPER", sender, true, "newHist", i, v);
    end
  end
end

AM.Register("histSyncF", function(_, sender, data)
  syncRespond(true, sender, data);
end);

AM.Register("histSync", function(_, sender, data)
  syncRespond(false, sender, data);
end);

F.history.setTooltip = function(itemString)
  local baseId = string.match(itemString, "^%d+");
  if PD.tooltip_cache[baseId] then
    local entries = {};
    for i=1,#PD.tooltip_cache[baseId] do
      local e = PD.table_itemHistory[PD.tooltip_cache[baseId][i]];
      if not e then
        error("Tooltip cache points to nil history entry.");
      end
      
      local bonusStr = string.match(e.itemString, "^%d-:(.+)");
      local bonusT = {};
      while bonusStr and string.match(bonusStr, "%d") do
            table.insert(bonusT, tonumber(string.match(bonusStr, "%d+")));
	bonusStr = string.gsub(bonusStr, "%d+:?", "", 1);
      end
      
      local dLabel = "Normal";
      local tooltipBonusStr = "";
      for j=1,#bonusT do
        if SD.bonusIDDescriptors[bonusT[j]] then
	  local l = SD.bonusIDDescriptors[bonusT[j]];
	  if SD.difficultyBonusIDs[bonusT[j]] then
	    dLabel = l;
	  else
	    if tooltipBonusStr ~= "" then
	      tooltipBonusStr = tooltipBonusStr .. ", ";
	    end
	    tooltipBonusStr = tooltipBonusStr .. l;
	  end
	end
      end
      entries[dLabel] = entries[dLabel] or {};
      table.insert(entries[dLabel], {PD.tooltip_cache[baseId][i], tooltipBonusStr});
    end
    
    for i,v in pairs(entries) do
      GameTooltip:AddLine(string.format("\n|c%s%s|r Item History (%s):", A.COLOR, A.NAME, i));
      for j=1,#v do
        local e = PD.table_itemHistory[v[j][1]];
	
        local w = string.match(e.winner, "^[^-]+");
        local d = date("%x", e.date);
        GameTooltip:AddDoubleLine(string.format("%s - %s |cFFFF0000%s|r", d, w, v[j][2]), string.format("%d DKP", e.value));
      end
    end
  end
end
