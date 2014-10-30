local A = FALoot;
A.util = {};
local U = A.util;
local SD = A.sData;
local PD = A.pData;

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

U.ItemLinkStrip = function(itemLink)
  if not itemLink then
    U.debug("util.ItemLinkStrip was passed a nil value!", 1);
    return;
  elseif type(itemLink) ~= "string" then
    U.debug("util.ItemLinkStrip was passed a non-string value!", 1);
    return;
  end
  
  local _, _, linkColor, linkType, itemId, enchantId, gemId1, gemId2, gemId3, gemId4, suffixId, uniqueId, linkLevel, reforgeId, itemName =
  string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):%d+|?h?%[?([^%[%]]*)%]?|?h?|?r?")
  if itemId and suffixId then
    suffixId = tonumber(suffixId);
    -- super hacky workaround for blizzard's weird suffixId system
    if suffixId > 60000 then
      suffixId = suffixId - 65536;
    end
    local s = itemId..":"..suffixId;
    -- U.debug(s, 3);
    return s;
  end
end

U.ItemLinkAssemble = function(itemString)
  if string.match(itemString, "^%d+:%-?%d+") then
    local itemId, suffixId, srcGUID = string.match(itemString, "^(%d+):(%-?%d+)");
    local fullItemString = "item:"..itemId..":0:0:0:0:0:"..suffixId;
    local _, link = GetItemInfo(fullItemString);
    if not link then
      return;
    end
    U.debug(link, 3);
    return link;
  end
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

U.isGuildGroup = function(threshold)
  GuildRoster()
  local groupType
  if IsInRaid() then
    groupType = "raid"
  else
    groupType = "party"
  end
  local numguildies = 0
  local numOffline = 0
  for i=1,GetNumGroupMembers() do
    local iname = GetRaidRosterInfo(i)
    if iname then
      if U.isNameInGuild(iname) then
        numguildies = numguildies + 1
      end
      if not UnitIsConnected(groupType..i) then
        numOffline = numOffline + 1
      end
    end
  end
  if (numguildies/(GetNumGroupMembers()-numOffline) > threshold) then
    return true
  else
    return false
  end
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
  local showOffline = GetGuildRosterShowOffline();
  SetGuildRosterShowOffline(false);
  for i=1,40 do
    if UnitExists(groupType..i) then
      local name = GetRaidRosterInfo(i)
      local _, onlineguildies = GetNumGuildMembers()
      for j=1,onlineguildies do
        local _, rankName, rankIndex = GetGuildRosterInfo(j)
        if string.match(rankName, "Aspect") then
          aspects = aspects + 1
        elseif  string.match(rankName, "Drake") then
          drakes = drakes + 1
        end
      end
    end
  end
  SetGuildRosterShowOffline(showOffline);
  if aspects >= 2 and drakes >= 5 then
    return true
  else
    return false
  end
end

A.isEnabled = function(overrideDebug)
  if not overrideDebug and PD.debugOn > 0 then
    return 1
  end
  
  local _, instanceType = IsInInstance()
  
  if not isGuildGroup(0.60) then
    return nil, "not guild group"
  elseif not U.isMainRaid() then
    return nil, "not enough officers"
  elseif instanceType ~= "raid" then
    return nil, "wrong instance type"
  elseif not (GetRaidDifficultyID() == 4 or GetRaidDifficultyID() == 6) then
    return nil, "wrong instance difficulty"
  elseif GetNumGroupMembers() < 20 then
    return nil, "not enough group members"
  else
    return 1
  end
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
  if not (class == "Armor" or class == "Weapon" or (class == "Miscellaneous" and subClass == "Junk")) then
    U.debug("Class of "..itemLink.." is incorrect.", 1)
    return false
  end
  
  -- check if the item level of the item is high enough
  if checkItemLevel then
    local playerTotal = GetAverageItemLevel()
    if playerTotal - ilevel > 60 then -- if the item is more than 60 levels below the player
      U.debug("Item Level of "..itemLink.." is too low.", 1);
      return false
    end
  end
  
  return true
end