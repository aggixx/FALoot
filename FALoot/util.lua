local A = FALoot;
A.util = {};
local U = A.util;
local SD = A.sData;
local PD = A.pData;
local E = A.events;

SD.debugData = {};
PD.debugOn = 0;

--[[ =======================================================
     Utility / Helper Functions
     ======================================================= --]]

U.formatDebugData = function()
  local s = ""
  for i=1,#debugData do
    if i > 1 then
      s = s .. "\n";
    end
    s = s .. "[" .. date("%c", debugData[i].time) .. "]<" .. debugData[i].threshold .. "> " .. debugData[i].msg;
  end
  return s;
end;

U.debug = function(msg, verbosity)
  local output;
  if type(msg) == "string" or type(msg) == "number" or type(msg) == "nil" then
    output = msg or "nil";
  elseif type(msg) == "boolean" then
    output = (msg and "true") or "false";
  elseif type(msg) == "table" then
    if DevTools_Dump then
      if not verbosity or PD.debugOn >= verbosity then
        DevTools_Dump(msg);
      end
      return;
    else
      output = "DevTools not found.";
    end
  else
    return;
  end
  table.insert(SD.debugData, {
    ["msg"] = output,
    ["time"] = time(),
    ["threshold"] = verbosity or 0,
  });
  if not verbosity or PD.debugOn >= verbosity then
    print(A.CHAT_HEADER..output);
  end
end

U.deepCopy = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[U.deepCopy(orig_key)] = U.deepCopy(orig_value)
        end
        setmetatable(copy, U.deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

U.deepCompare = function(t1, t2, ignore_mt)
  local ty1 = type(t1)
  local ty2 = type(t2)
  if ty1 ~= ty2 then return false end
  -- non-table types can be directly compared
  if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
  -- as well as tables which have the metamethod __eq
  local mt = getmetatable(t1)
  if not ignore_mt and mt and mt.__eq then return t1 == t2 end
  for k1,v1 in pairs(t1) do
    local v2 = t2[k1]
    if v2 == nil or not U.deepCompare(v1,v2) then return false end
  end
  for k2,v2 in pairs(t2) do
    local v1 = t1[k2]
    if v1 == nil or not U.deepCompare(v1,v2) then return false end
  end
  return true
end

-- custom UnitName
U.UnitName = function(unit, showServer)
  local name = UnitName(unit, showServer);
  if showServer and name and not string.match(name, "-") then
    name = name .. "-" .. SD.PLAYER_REALM;
  end
  return name;
end

-- custom GetRaidRosterInfo
U.GetRaidRosterInfo = function(index)
  local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(index);
  return (U.UnitName("raid"..index, true) or name), rank, subgroup, level, class, fileName, zone, online, isDead, role, isML;
end

-- Get current server timestamp
U.GetCurrentServerTime = function()
  local _, hours, minutes = GameTime_GetGameTime(true);
  local _, month, day, year = CalendarGetDate();
  local currentServerTime = time({
    ["hour"] = hours,
    ["min"] = minutes,
    ["month"] = month,
    ["day"] = day,
    ["year"] = year,
  });
  return currentServerTime;
end

-- As of 6.0.2:
-- itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:specId:upgradeId:instanceDifficultyID:numBonusIDs:bonusID1:bonusID2...:upgradeValue

U.ItemLinkStrip = function(itemLink)
  if not itemLink then
    U.debug("util.ItemLinkStrip was passed a nil value!", 1);
    return;
  elseif type(itemLink) ~= "string" then
    U.debug("util.ItemLinkStrip was passed a non-string value!", 1);
    return;
  end
  
  local itemString = string.match(itemLink, "|c%x+|Hitem:(.-)|h%[.-]|h|r");
  
  if not itemString then
	U.debug("util.ItemLinkStrip was passed a string that does not eval to an itemString.", 1);
	return;
  end
  
  local out = "";
  local i = 1;
  local numBonuses;
  local itemId = "";
  local suffixId = "";
  local upgradeId = "";
  local bonusIds = "";
  
  for id in string.gmatch(itemString, "(%-?%d*):?") do
    id = tonumber(id);
    
	if i == 13 then
		numBonuses = id or 0;
	elseif i == 1 then -- itemID
	  itemId = id;
	elseif i == 7 then -- suffixID
	  suffixId = id;
	elseif i > 13 and i <= 13 + numBonuses then -- bonusIDs
	  if i > 14 then
	    bonusIds = bonusIds .. ":"
	  end
	  if i == 7 and id and id > 60000 then -- ugly hack to account for suffix system
		id = id - 65536;
	  end
	  bonusIds = bonusIds .. ( id or 0 );
	end
    
    i = i + 1;
  end
  
  return format("%d:%d:%s", itemId, suffixId, bonusIds);
end

U.ItemLinkAssemble = function(itemString)
  local itemId, suffixId, bonusIds = string.match(itemString, "(%d+):(%d+):([%d:]+)");
  print(itemId, suffixId, bonusIds);
  local numBonus = select(2, bonusIds:gsub("%d+", ""));
  print(numBonus);
  
  local s = format("item:%d::::::%s::::::%s:%s", itemId, suffixId, numBonus, bonusIds);
  print(s);
      
  local _, link = GetItemInfo(s);
  if not link then
    return;
  end
    
  return link;
end

U.isNameInGuild = function(name)
  local showOffline = GetGuildRosterShowOffline();
  SetGuildRosterShowOffline(false);
  local _, onlineguildies = GetNumGuildMembers();
  for j=1,onlineguildies do
    local jname = GetGuildRosterInfo(j);
    if jname == name then
      return true;
    end
  end
  SetGuildRosterShowOffline(showOffline);
end

U.isMainRaid = function()
  GuildRoster()
  local groupType
  if IsInRaid() then
    groupType = "raid"
  else
    groupType = "party"
  end
  local aspects, drakes = 0, 0;
  
  -- save show offline state to restore later
  local showOffline = GetGuildRosterShowOffline();
  SetGuildRosterShowOffline(false);
  
  --[[ create table of guild member data so we don't have to
       call GetGuildRosterInfo a zillion times. --]]
  local guild = {};
  for i=1,select(2, GetNumGuildMembers()) do
    local name, rank = GetGuildRosterInfo(i);
    guild[i] = {};
    guild[i].name = string.match(name, "^[^-]+");
    guild[i].rank = rank;
  end
  
  -- compare our table of data with the people in the raid
  for i=1,40 do
    if UnitExists(groupType..i) then
      local rName = GetRaidRosterInfo(i), "^[^-]+";
      for j=1,#guild do
	if rName == guild[j].name then
          if string.match(guild[j].rank, "Aspect") then
            aspects = aspects + 1
          elseif guild[j].rank == "Drake" then
            drakes = drakes + 1
          end
	  break;
	end
      end
    end
  end
  
  -- restore show offline state
  SetGuildRosterShowOffline(showOffline);
  
  if aspects >= 2 and drakes >= 5 then
    return true
  else
    return false, aspects, drakes
  end
end

do
  local cache;
  
  -- Create function to be called when isEnabled's result may have changed.
  local function wipeCache()
    cache = nil;
    U.debug("Addon enabled state wiped.", 2);
  end
  
  -- Only get a new result if we don't have a cached one (or the old cached value has been cleared).
  A.isEnabled = function(overrideDebug)
    if not overrideDebug and PD.debugOn > 0 then
      return true;
    end
    
    if cache then
      return cache;
    end
    
    -- do efficient methods first
    if select(2, IsInInstance()) ~= "raid" then
      cache = false;
      return cache, "wrong instance type";
    end
    
    local n = GetNumGroupMembers();
  
    if n < 10 then
      cache = false;
      return cache, "not enough group members";
    end
  
    local d = GetRaidDifficultyID();
  
    if not (d == 15 or d == 16) then
      cache = false;
      return cache, "wrong instance difficulty";
    elseif select(2, InGuildParty())/n < 0.75 then
      cache = false;
      return cache, "not guild group";
    --[[elseif not U.isMainRaid() then
      cache = false;
      return cache, "not enough officers";]]
    end
  
    cache = true;
    return cache;
  end
  
  -- Set events for cache to be cleared
  
  local eventFrame = CreateFrame("Frame");
  eventFrame:SetScript("OnEvent", wipeCache);
  eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED");
  
  E.Register("GROUP_ROSTER_UPDATE", wipeCache);
  E.Register("ZONE_CHANGED_NEW_AREA", wipeCache);
end

U.checkFilters = function(itemString, checkItemLevel)
  -- itemString must be a string!
  if type(itemString) ~= "string" then
    U.debug("checkFilters was passed a non-string value!", 1);
    return;
  end

  --this is the function that determines if an item should or shouldn't be added to the window and/or announced
  local itemLink = U.ItemLinkAssemble(itemString);
  
  if not itemLink then
    U.debug("checkFilters: Unable to retrieve itemLink! itemString = "..itemString..", itemLink = "..(itemLink or ""), 1);
    return false;
  end
  
  if PD.debugOn > 0 then
    return true
  end
  
  -- check properties of item
  local _, _, quality, ilevel, _, class, subClass = GetItemInfo(itemLink)
  
  -- check if the quality of the item is high enough
  if quality ~= 4 then -- TODO: Add customizable quality filters
    U.debug("Quality of "..itemLink.." is too low.", 1);
    return false
  end
    
  -- check if the class of the item is appropriate
  if class == "Miscellaneous" and subClass == "Junk" then
    return true;
  end
  
  if not (class == "Armor" or class == "Weapon") then
    U.debug("Class of "..itemLink.." is incorrect.", 1)
    return false
  end
  
  -- check if the item level of the item is high enough
  if checkItemLevel or class then
    local playerTotal = GetAverageItemLevel()
    if playerTotal - ilevel > 60 then -- if the item is more than 60 levels below the player
      U.debug("Item Level of "..itemLink.." is too low.", 1);
      return false
    end
  end
  
  return true
end
