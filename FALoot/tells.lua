local A = FALoot;
local U = A.util;
local SD = A.sData;
local PD = A.pData;
local O = A.options;
local E = A.events;
local AM = A.addonMessages;
local CM = A.chatMessages;
local F = A.functions;
local UI = A.UI;

-- Call Libraries
local ScrollingTable = LibStub("ScrollingTable");

-- Init some tables
SD.table_tells = {};

-- Local variables
local requestPending;

--[[ ==========================================================================
     GUI Creation
     ========================================================================== --]]
     
local function createGUI()
	UI.tellsWindow = {};

	-- Create the main frame
	local tellsFrame = CreateFrame("frame", "FALootTellsFrame", UIParent)
	tellsFrame:EnableMouse(true);
	tellsFrame:SetMovable(true);
	tellsFrame:SetFrameStrata("FULLSCREEN_DIALOG");
	tellsFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	});
	tellsFrame:SetBackdropColor(0, 0, 0, 1);
	tellsFrame:SetToplevel(true);
	tellsFrame:SetWidth(348);
	tellsFrame:SetHeight(184);
	tellsFrame:SetPoint("CENTER");
	tellsFrame:Hide();
	
	UI.tellsWindow.frame = tellsFrame;

	-- Create the background of the title
	local tellsTitleBg = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg:SetTexCoord(0.31, 0.67, 0, 0.63)
	tellsTitleBg:SetPoint("TOP", 0, 12)
	tellsTitleBg:SetHeight(40)
	
	-- Create the title frame
	local tellsTitle = CreateFrame("Frame", nil, tellsFrame)
	tellsTitle:EnableMouse(true)
	tellsTitle:SetScript("OnMouseDown", function(frame)
		frame:GetParent():StartMoving()
	end)
	tellsTitle:SetScript("OnMouseUp", function(frame)
		frame:GetParent():StopMovingOrSizing()
	end)
	tellsTitle:SetAllPoints(tellsTitleBg)

	-- Create the text of the title
	local tellsTitleText = tellsTitle:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	tellsTitleText:SetPoint("TOP", tellsTitleBg, "TOP", 0, -14);
	
	UI.tellsWindow.title = tellsTitleText;
	UI.tellsWindow.titleBg = tellsTitleBg;
	
	tellsTitleBg:SetWidth((tellsTitleText:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local tellsTitleBg_l = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	tellsTitleBg_l:SetPoint("RIGHT", tellsTitleBg, "LEFT")
	tellsTitleBg_l:SetWidth(30)
	tellsTitleBg_l:SetHeight(40)

	-- Create the title background right edge
	local tellsTitleBg_r = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	tellsTitleBg_r:SetPoint("LEFT", tellsTitleBg, "RIGHT")
	tellsTitleBg_r:SetWidth(30)
	tellsTitleBg_r:SetHeight(40)
	
	-- Create the scrollingTable
	local tellsTable = ScrollingTable:CreateST({
		{
			["name"] = "Name",
			["width"] = 90,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Rank",
			["width"] = 60,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Bid",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Roll",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Flags",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
	}, 6, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, tellsFrame);
	tellsTable:EnableSelection(true);
	tellsTable.frame:SetPoint("TOP", tellsTitleBg, "BOTTOM", 0, -10);
	tellsTable.frame:SetScale(1.1);
	
	UI.tellsWindow.scrollingTable = tellsTable;
	
	-- Create the flag count mouseover frames
	local flagMouseovers = {};
	for i=1,6 do
		flagMouseovers[i] = CreateFrame("frame", tellsFrame:GetName().."STFlagOverlay"..tostring(i), tellsTable.frame)
		flagMouseovers[i]:SetWidth(66)
		flagMouseovers[i]:SetHeight(14.5)
		flagMouseovers[i]:SetFrameLevel(flagMouseovers[i]:GetFrameLevel() + 1);
		if i == 1 then
			flagMouseovers[i]:SetPoint("TOPRIGHT", tellsTable.frame, "TOPRIGHT", -3, -5);
		else
			flagMouseovers[i]:SetPoint("TOP", flagMouseovers[i-1], "BOTTOM", 0, -1);
		end
		
		flagMouseovers[i]:SetScript("OnEnter", function(self)
			local num = tonumber(string.match(self:GetName(), "%d$"));
			if SD.tellsInProgress and SD.table_items[SD.tellsInProgress].tells[num] and (SD.table_items[SD.tellsInProgress].tells[num][5] or 0) > 0 then
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
				local player = SD.table_items[SD.tellsInProgress]["tells"][num][1];
				local currentServerTime = U.GetCurrentServerTime();
				
				GameTooltip:AddLine("Possible MS items won this raid: \n");
				
				for j=#SD.table_itemHistory,1,-1 do
					if currentServerTime-SD.table_itemHistory[j].time <= 60*60*12 then
						if SD.table_itemHistory[j].winner == player and SD.table_itemHistory[j].bid ~= 20 then
							-- Calculate and format time elapsed
							local eSecs = currentServerTime-SD.table_itemHistory[j].time;
							local eMins = math.ceil(eSecs/60);
							local eHrs  = math.floor(eMins/60);
							eMins       = eMins - 60*eHrs;
							local eStr = eMins.."m ago";
							if eHrs > 0 then
								eStr = eHrs .. "h" .. eStr;
							end
							eStr = "~" .. eStr;
							
							GameTooltip:AddDoubleLine(U.ItemLinkAssemble(SD.table_itemHistory[j].itemString), eStr);
							GameTooltip:AddLine("  - Cost: " .. SD.table_itemHistory[j].bid .. " DKP");
						else
							U.debug("Entry is not from the appropriate player.", 1);
						end
					else
						break;
					end
				end
				
				GameTooltip:Show();
			end
		end);
		flagMouseovers[i]:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
		
		flagMouseovers[i]:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			tile = true, tileSize = 32,
		});
		flagMouseovers[i]:SetBackdropColor(1, 1, 1, 0);
	end
	
	-- Create the Tell Window Award button
	local tellsFrameAwardButton = CreateFrame("Button", tellsFrame:GetName().."AwardButton", tellsFrame, "UIPanelButtonTemplate")
	tellsFrameAwardButton:SetPoint("BOTTOMLEFT", 15, 15)
	tellsFrameAwardButton:SetHeight(20)
	tellsFrameAwardButton:SetWidth(154)
	tellsFrameAwardButton:SetText("Award Item")
	tellsFrameAwardButton:SetScript("OnClick", function(frame)
		local selection = tellsTable:GetSelection();
		if selection then
			-- Send a chat message with the winner for those that don't have the addon
			local winnerNoRealm = string.match(SD.table_items[SD.tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
			SendChatMessage(SD.table_items[SD.tellsInProgress]["itemLink"].." "..winnerNoRealm, "RAID");
			
			-- Send an addon message for those with the addon
			local cST = U.GetCurrentServerTime();
			F.sendMessage("RAID", nil, true, "itemWinner", {
				["itemString"] = SD.tellsInProgress,
				["winner"] = SD.table_items[SD.tellsInProgress]["tells"][selection][1],
				["bid"] = SD.table_items[SD.tellsInProgress]["tells"][selection][3],
				["time"] = cST,
			});
			F.items.addWinner(SD.tellsInProgress, SD.table_items[SD.tellsInProgress]["tells"][selection][1], SD.table_items[SD.tellsInProgress]["tells"][selection][3], cST);
			
			-- Announce winner and bid amount to aspects chat
			local channels, channelNum = {GetChannelList()};
			for i=1,#channels do
				if string.lower(channels[i]) == "aspects" then
					channelNum = channels[i-1];
					break;
				end
			end
			if channelNum then
				-- I have no idea why but apparently if you don't manually define these as variables first it just errors out
				local link = SD.table_items[SD.tellsInProgress]["itemLink"];
				local winner = string.match(SD.table_items[SD.tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
				local bid = SD.table_items[SD.tellsInProgress]["tells"][selection][3];
				SendChatMessage(link.." "..winner.." "..bid, "CHANNEL", nil, channelNum);
			end
			
			table.remove(SD.table_items[SD.tellsInProgress]["tells"], selection);
		end
	end);
	
	UI.tellsWindow.awardButton = tellsFrameAwardButton;
	
	-- Create the Tell Window Action button
	local tellsFrameActionButton = CreateFrame("Button", tellsFrame:GetName().."ActionButton", tellsFrame, "UIPanelButtonTemplate")
	tellsFrameActionButton:SetPoint("BOTTOMRIGHT", -15, 15)
	tellsFrameActionButton:SetHeight(20)
	tellsFrameActionButton:SetWidth(154)
	tellsFrameActionButton:SetText("Lower to 20")
	tellsFrameActionButton:SetScript("OnClick", function(frame)
		--frame:GetParent():Hide();
	end);
	
	UI.tellsWindow.actionButton = tellsFrameActionButton;

	-- Create the "Take Tells" button
	local tellsButton = CreateFrame("Button", UI.itemWindow.frame:GetName().."TellsButton", UI.itemWindow.frame, "UIPanelButtonTemplate");
	tellsButton:SetScript("OnClick", function(self, event)
		local id = UI.itemWindow.scrollingTable:GetSelection()
		local j = 0;
		for i, v in pairs(SD.table_items) do
			j = j + 1;
			if j == id then
				-- We've figured out the item string of the corresponding item (i), so now let's ask for permission to post it.
				F.items.requestTakeTells(i);
				-- While we're waiting for a request to our response, let's make sure the user can't take tells on any more items.
				-- FIXME
				self:Disable();
				break;
			end
		end
	end)
	tellsButton:SetHeight(20);
	tellsButton:SetWidth(80);
	tellsButton:SetText("Take Tells");
	tellsButton:SetPoint("BOTTOM", UI.itemWindow.bidButton, "TOP");
	tellsButton:SetFrameLevel(UI.itemWindow.scrollingTable.frame:GetFrameLevel()+1);
	--tellsButton:Disable();
	--tellsButton:Hide();
	
	UI.itemWindow.tellsButton = tellsButton;
end

--[[ ==========================================================================
     Item Functions
     ========================================================================== --]]

-- === items.takeTells() ======================================================

F.items.takeTells = function(itemString)
  -- itemString must be a string!
  if type(itemString) ~= "string" then
    error('Usage: items.takeTells("itemString")');
  end
  
  if SD.table_items[itemString] and not SD.table_items[itemString]["status"] then
    SD.table_items[itemString]["tells"] = {};
    SD.tellsInProgress = itemString;
    UI.tellsWindow.title:SetText(SD.table_items[itemString]["displayName"]);
    UI.tellsWindow.titleBg:SetWidth((UI.tellsWindow.title:GetWidth() or 0) + 10);
    E.Trigger("TELLS_UPDATE");
    SendChatMessage(SD.table_items[itemString]["itemLink"].." 30", "RAID");
    UI.itemWindow.tellsButton:Disable();
  else
    U.debug("Item does not exist or is already in progress!", 1);
  end
end

-- === items.requestTakeTells() ===============================================

F.items.requestTakeTells = function(itemString)
  -- Make sure that this is an item we can actually take tells on before trying to submit a request
  if type(itemString) ~= "string" or not SD.table_items[itemString] or SD.table_items[itemString]["status"] or SD.table_items[itemString]["host"] then
    error('Usage: items.requestTakeTells("itemString")');
  end
  -- Acquire name of raid leader
  local raidLeader, raidLeaderUnitID;
  if IsInRaid() then
    for i=1,GetNumGroupMembers() do
      if UnitIsGroupLeader("raid"..i) and UnitIsConnected("raid"..i) then
        raidLeader = U.UnitName("raid"..i, true);
        raidLeaderUnitID = "raid"..i;
        break;
      end
    end
  elseif PD.debugOn > 0 then
    -- For testing purposes, let's let the player act as the raid leader.
    raidLeader = SD.PLAYER_NAME;
  else
    U.debug("You must be in a raid to do that.");
    return;
  end
  if raidLeader and raidLeader == "Unknown" then
    error("Raid leader was found, but returned name Unknown.");
  elseif raidLeader then
    -- Set itemString to become the active tells item
    SD.tellsInProgress = itemString;
    if (raidLeaderUnitID and UnitIsConnected(raidLeaderUnitID)) or (not IsInRaid() and PD.debugOn > 0) then
      -- Ask raid leader for permission to start item
      U.debug('Asking Raid leader "' .. raidLeader .. '" for permission to post item (' .. itemString .. ').', 1);
      F.sendMessage("WHISPER", raidLeader, false, "postRequest", itemString);
      -- Set request timer
      requestPending = true;
      C_Timer.After(PD.postRequestMaxWait, function()
        if requestPending then
          U.debug(PD.postRequestMaxWait .. " seconds have elapsed with no response from raid leader, posting item (" .. SD.tellsInProgress .. ") anyway.", 1);
          F.items.takeTells(SD.tellsInProgress);
	  requestPending = nil;
	end
      end);
    else
      -- Leader is offline, so let's just go ahead post the item.
      U.debug('Raid leader "' .. raidLeader .. '" is offline, skipping redundancy check.', 1);
      F.items.takeTells(itemString);
    end
  else
    error("Could not find Raid leader.");
  end
end

--[[ ==========================================================================
     FALoot Events
     ========================================================================== --]]
     
-- === Tells Window update =====================================================

E.Register("TELLSWINDOW_UPDATE", function()
  if not (SD.tellsInProgress and SD.table_items[SD.tellsInProgress]) then
    return;
  elseif SD.table_items[SD.tellsInProgress]["status"] == "Ended" then
    SD.tellsInProgress = nil;
    UI.tellsWindow.frame:Hide();
    return;
  end
    
	-- Set rank data
	GuildRoster()
	local showOffline = GetGuildRosterShowOffline();
	SetGuildRosterShowOffline(true);

	for i=1,#SD.table_items[SD.tellsInProgress]["tells"] do
		local name, rank = SD.table_items[SD.tellsInProgress]["tells"][i][1], SD.table_items[SD.tellsInProgress]["tells"][i][2];
		
		if not rank then
			SD.table_items[SD.tellsInProgress]["tells"][i][2] = "";
			for j=1,GetNumGuildMembers() do
				local currentName, rankName = GetGuildRosterInfo(j)
				if currentName == name then
					if rankName == "Aspect" or rankName == "Aspects" or rankName == "Dragon" or rankName == "Drake" then
						SD.table_items[SD.tellsInProgress]["tells"][i][2] = "Drake";
					elseif rankName == "Whelp" then
						SD.table_items[SD.tellsInProgress]["tells"][i][2] = "Whelp";
					else
						SD.table_items[SD.tellsInProgress]["tells"][i][2] = "Wyrm";
					end
					break;
				end
			end
		end
	end

	SetGuildRosterShowOffline(showOffline);

	-- Count flags
	local currentServerTime = U.GetCurrentServerTime();
	for i=1,#SD.table_items[SD.tellsInProgress].tells do
		local flags = 0;
		if SD.table_itemHistory then
			for j=#SD.table_itemHistory,1,-1 do
				if currentServerTime-SD.table_itemHistory[j].time <= 60*60*12 then
					if SD.table_itemHistory[j].winner == SD.table_items[SD.tellsInProgress].tells[i][1] and SD.table_itemHistory[j].bid ~= 20 then
						flags = flags + 1;
					end
				else
					break;
				end
			end
		end
		SD.table_items[SD.tellsInProgress].tells[i][5] = flags;
	end

	-- Sort table
	table.sort(SD.table_items[SD.tellsInProgress]["tells"], function(a, b)
		if a[2] ~= b[2] then
			if a[2] == "Drake" then
				return true;
			elseif b[2] == "Drake" then
				return false;
			else
				if a[2] == "Whelp" then
					return true;
				else
					return false;
				end
			end
		elseif (tonumber(a[4]) or 0) ~= (tonumber(b[4]) or 0) then
			return (tonumber(a[4]) or 0) > (tonumber(b[4]) or 0);
		else				
			return a[3] > b[3];
		end
	end)

	-- Make a copy of the item entry so we can make our modifications without affecting the original
	local t = U.deepCopy(SD.table_items[SD.tellsInProgress]);

	--[[-- Purge any entries that are lower than what we want to display right now
	local limit = #t["tells"];
	for i=0,limit-1 do
		if t["tells"][limit-i][3] < t["currentValue"] then
			table.remove(t["tells"], limit-i);
		end
	end--]]

	-- Set name color
	for i=1,#t["tells"] do
		if not string.match(t["tells"][i][1], "|c%x+.|r") then
			local groupType = (IsInRaid() and "raid") or "party";
			for j=1,GetNumGroupMembers() do
				if t["tells"][i][1] == U.UnitName(groupType..j, true) then
					local _, class = UnitClass(groupType..j);
					t["tells"][i][1] = "|c" .. RAID_CLASS_COLORS[class]["colorStr"] .. U.UnitName(groupType..j, false) .. "|r";
					break;
				end
			end
		end
	end

	local isCompetition;
	local numWinners = 0;
	for i, v in pairs(SD.table_items[SD.tellsInProgress]["winners"]) do
		numWinners = numWinners + #v;
	end

	-- Colorize bid values
	if #t["tells"] <= t["quantity"] - numWinners then -- If there's enough items for everyone then just set everything to green
		for i=1,#t["tells"] do
			t["tells"][i][3] = "|cFF00FF00" .. t["tells"][i][3] .. "|r";
		end
	else
		local tellsByRank, currentRank, j = {}, nil, 0;
		if t["currentValue"] > 10 then
			for i=1,#t["tells"] do
				if not currentRank or currentRank ~= t["tells"][i][2] then
					currentRank = t["tells"][i][2];
					j = j + 1;
					tellsByRank[j] = {};
				end
				table.insert(tellsByRank[j], t["tells"][i][1]);
			end
		else
			tellsByRank[1] = {}
			for i=1,#t["tells"] do
				table.insert(tellsByRank[1], t["tells"][i][1]);
			end
		end
		
		local itemsLeft = t["quantity"] - numWinners;
		for i=1,#tellsByRank do
			if #tellsByRank[i] <= itemsLeft then
				for j=1,#tellsByRank[i] do
					for k=1,#t["tells"] do
						if t["tells"][k][1] == tellsByRank[i][j] then
							t["tells"][k][3] = "|cFF00FF00" .. t["tells"][k][3] .. "|r"
							break;
						end
					end
				end
				
				itemsLeft = itemsLeft - #tellsByRank[i];
			elseif itemsLeft == 0 then
				for j=1,#tellsByRank[i] do
					for k=1,#t["tells"] do
						if t["tells"][k][1] == tellsByRank[i][j] then
							t["tells"][k][3] = "|cFFFF0000" .. t["tells"][k][3] .. "|r"
							break;
						end
					end
				end
			else
				-- Find the green threshold
				for j=1,#t["tells"] do
					if t["tells"][j][1] == tellsByRank[i][itemsLeft+1] then
						tellsGreenThreshold = t["tells"][j][3] + 60;
						break;
					end
				end
				
				-- Find the yellow threshold
				for j=1,#t["tells"] do
					if t["tells"][j][1] == tellsByRank[i][itemsLeft] then
						tellsYellowThreshold = max(t["tells"][j][3] - 58, t["currentValue"]);
						break;
					end
				end
				
				-- Colorize items based on green and yellow thresholds
				for j=1,#tellsByRank[i] do
					for k=1,#t["tells"] do
						if t["tells"][k][1] == tellsByRank[i][j] then
							tellsRankThreshold = t["tells"][k][2];
							if t["tells"][k][3] >= tellsGreenThreshold then
								t["tells"][k][3] = "|cFF00FF00" .. t["tells"][k][3] .. "|r";
							elseif t["tells"][k][3] >= tellsYellowThreshold then
								t["tells"][k][3] = "|cFFFFFF00" .. t["tells"][k][3] .. "|r";
								isCompetition = true;
							else
								t["tells"][k][3] = "|cFFFF0000" .. t["tells"][k][3] .. "|r";
							end
							break;
						end
					end
				end
				
				itemsLeft = 0;
			end
		end
	end

	UI.tellsWindow.scrollingTable:SetData(t["tells"], true);

	-- Set button text and script
	if isCompetition and SD.table_items[SD.tellsInProgress]["tells"][1][3] >= t["currentValue"] then
		if UI.tellsWindow.actionButton:GetButtonState() ~= "DISABLED" then
			UI.tellsWindow.actionButton:Enable();
			UI.tellsWindow.actionButton:SetText("Roll!");
			UI.tellsWindow.actionButton:SetScript("OnClick", function(self)
				SendChatMessage(SD.table_items[SD.tellsInProgress]["itemLink"].." roll", "RAID");
				self:SetText("Waiting for rolls...");
				self:Disable();
			end)
		end
	elseif SD.table_items[SD.tellsInProgress]["currentValue"] > 10 then
		UI.tellsWindow.actionButton:Enable();
		UI.tellsWindow.actionButton:SetText("Lower to "..SD.table_items[SD.tellsInProgress]["currentValue"]-10);
		UI.tellsWindow.actionButton:SetScript("OnClick", function()
			SendChatMessage(SD.table_items[SD.tellsInProgress]["itemLink"].." "..SD.table_items[SD.tellsInProgress]["currentValue"]-10, "RAID");
		end)
	else
		UI.tellsWindow.actionButton:Enable();
		UI.tellsWindow.actionButton:SetText("Disenchant");
		UI.tellsWindow.actionButton:SetScript("OnClick", function()
			local channels, channelNum = {GetChannelList()};
			for i=1,#channels do
				if string.lower(channels[i]) == "aspects" then
					channelNum = channels[i-1];
					break;
				end
			end
			if channelNum then
				SendChatMessage(SD.table_items[SD.tellsInProgress]["itemLink"].." disenchant", "CHANNEL", nil, channelNum);
			end
		end)
	end

	UI.tellsWindow.frame:Show();
end);

-- === Tells Button visibility handler ========================================

E.Register("TELLSBUTTON_UPDATE", function()
	if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") or PD.debugOn > 0 then
		UI.itemWindow.tellsButton:Show();
	else
		UI.itemWindow.tellsButton:Hide();
	end
end);

-- === GUI Initiator ==========================================================

E.Register("PLAYER_LOGIN", function()
	createGUI();
	E.Trigger("TELLSBUTTON_UPDATE");
end);

-- postRequest message handler ================================================

AM.Register("postRequest", function(channel, sender, requestedItem)
  -- validate input
  if requestedItem then
    U.debug("Requested item: " .. requestedItem, 1);
  else
    return;
  end

  local okay = false;
  
  if not SD.table_items[requestedItem] then
    U.debug("Item does not exist, denying request.", 1);
  elseif SD.table_items[requestedItem]["status"] then
    U.debug("Item is already in progress, denying request.", 1);
  elseif SD.table_items[requestedItem]["host"] then
    U.debug('Item has already been claimed for posting by "' .. SD.table_items[requestedItem]["host"] .. '", denying request.', 1);
  else
    U.debug('Request granted.', 1);
    SD.table_items[requestedItem]["host"] = sender;
    okay = true;
  end
  
  F.sendMessage("WHISPER", sender, false, "postReply", okay);
end);

-- postReply message handler ==================================================

AM.Register("postReply", function(_, _, allowed)
  if SD.tellsInProgress and requestPending then
    if allowed then
      U.debug('Request to post item "' .. SD.tellsInProgress .. '" has been granted. Posting...', 1);
      F.items.takeTells(SD.tellsInProgress);
    else
      U.debug('Request to post item "' .. SD.tellsInProgress .. '" has been denied. Item abandoned.', 1);
      -- cancel the item in progress
      SD.tellsInProgress = nil;
      -- force a button state update
      E.Trigger("TELLSBUTTON_UPDATE");
    end
    
    requestPending = nil;
  end
end);

-- Bid message handler ========================================================

CM.Register("WHISPER", function(sender, msg)
  	U.debug("Parsing a whisper.", 2);
	if not SD.tellsInProgress then
		return;
	end
	if not SD.table_items[SD.tellsInProgress] then
		U.debug("Item in progress does not exist.", 1);
		SD.tellsInProgress = nil;
		return;
	end
	local bid, spec;
	if string.match(msg, "^%s*%d+%s*$") then
		bid = string.match(msg, "^%s*(%d+)%s*$");
	elseif string.match(msg, "^%s*%d+%s[MmOo][Ss]%s*$") then
		bid, spec = string.match(msg, "^%s*(%d+)%s([MmOo][Ss])%s*$");
	elseif string.match(msg, "^%s*"..SD.HYPERLINK_PATTERN.."%s?%d+$") then
		bid = string.match(msg, "^%s*"..SD.HYPERLINK_PATTERN.."%s?(%d+)$");
	elseif string.match(msg, "^%d+%s?"..SD.HYPERLINK_PATTERN.."$") then
		bid = string.match(msg, "^(%d+)%s?"..SD.HYPERLINK_PATTERN.."$");
	elseif string.lower(msg) == "pass" then
		for i=1,#SD.table_items[SD.tellsInProgress]["tells"] do
			if SD.table_items[SD.tellsInProgress]["tells"][i][1] == author then
				table.remove(SD.table_items[SD.tellsInProgress]["tells"], i);
				E.Trigger("TELLSWINDOW_UPDATE");
				break;
			end
		end
		return;
	else
		return;
	end
	bid = tonumber(bid);
	
	local groupType, inGroup;
	if IsInRaid() then
		groupType = "raid";
	else
		groupType = "party";
	end
	for i=1,GetNumGroupMembers() do
		if U.UnitName(groupType..i, true) == sender then
			inGroup = true;
			break;
		end
	end
	if not inGroup then
		return;
	end
	
	local bidUpdated;
	for i=1,#SD.table_items[SD.tellsInProgress]["tells"] do
		if SD.table_items[SD.tellsInProgress]["tells"][i][1] == sender then
			SD.table_items[SD.tellsInProgress]["tells"][i][3] = bid;
			SendChatMessage("<FA Loot> Updated your bid for "..SD.table_items[SD.tellsInProgress]["itemLink"]..".", "WHISPER", nil, sender);
			bidUpdated = true;
			break;
		end
	end
	if not bidUpdated then
		table.insert(SD.table_items[SD.tellsInProgress]["tells"], {sender, nil, bid, ""});
		SendChatMessage("<FA Loot> Bid for "..SD.table_items[SD.tellsInProgress]["itemLink"].." accepted.", "WHISPER", nil, sender);
	end
	E.Trigger("ITEM_UPDATE");
	E.Trigger("TELLSWINDOW_UPDATE");
end);
     
--[[ ==========================================================================
     API Events
     ========================================================================== --]]

local eventFrame, events = CreateFrame("Frame"), {}

-- === Tells Button visibility triggers =======================================

function events:GROUP_ROSTER_UPDATE()
  E.Trigger("TELLSBUTTON_UPDATE");
end

function events:RAID_ROSTER_UPDATE()
  E.Trigger("TELLSBUTTON_UPDATE");
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end);
for k, v in pairs(events) do
  eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end