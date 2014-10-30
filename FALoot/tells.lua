local A = FALoot;
local U = A.util;
local SD = A.sData;
local PD = A.pData;
local O = A.options;
local E = A.events;
local M = A.messages;
local F = A.functions;
local UI = A.UI;

-- Call Libraries
local ScrollingTable = LibStub("ScrollingTable");

-- Init some tables
SD.table_tells = {};

-- Local variables
local tellsInProgress;
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
			if tellsInProgress and table_items[tellsInProgress].tells[num] and (table_items[tellsInProgress].tells[num][5] or 0) > 0 then
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
				local player = table_items[tellsInProgress]["tells"][num][1];
				local currentServerTime = U.GetCurrentServerTime();
				
				GameTooltip:AddLine("Possible MS items won this raid: \n");
				
				for j=#table_itemHistory,1,-1 do
					if currentServerTime-table_itemHistory[j].time <= 60*60*12 then
						if table_itemHistory[j].winner == player and table_itemHistory[j].bid ~= 20 then
							-- Calculate and format time elapsed
							local eSecs = currentServerTime-table_itemHistory[j].time;
							local eMins = math.ceil(eSecs/60);
							local eHrs  = math.floor(eMins/60);
							eMins       = eMins - 60*eHrs;
							local eStr = eMins.."m ago";
							if eHrs > 0 then
								eStr = eHrs .. "h" .. eStr;
							end
							eStr = "~" .. eStr;
							
							GameTooltip:AddDoubleLine(U.ItemLinkAssemble(table_itemHistory[j].itemString), eStr);
							GameTooltip:AddLine("  - Cost: " .. table_itemHistory[j].bid .. " DKP");
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
			local winnerNoRealm = string.match(table_items[tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
			SendChatMessage(table_items[tellsInProgress]["itemLink"].." "..winnerNoRealm, "RAID");
			
			-- Send an addon message for those with the addon
			local cST = U.GetCurrentServerTime();
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["itemWinner"] = {
					["itemString"] = tellsInProgress,
					["winner"] = table_items[tellsInProgress]["tells"][selection][1],
					["bid"] = table_items[tellsInProgress]["tells"][selection][3],
					["time"] = cST,
				},
			}, "RAID");
			FALoot:itemAddWinner(tellsInProgress, table_items[tellsInProgress]["tells"][selection][1], table_items[tellsInProgress]["tells"][selection][3], cST);
			
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
				local link = table_items[tellsInProgress]["itemLink"];
				local winner = string.match(table_items[tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
				local bid = table_items[tellsInProgress]["tells"][selection][3];
				SendChatMessage(link.." "..winner.." "..bid, "CHANNEL", nil, channelNum);
			end
			
			table.remove(table_items[tellsInProgress]["tells"], selection);
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

--   === items.takeTells() ====================================================

F.items.takeTells = function(itemString)
  -- itemString must be a string!
  if type(itemString) ~= "string" then
    error('Usage: items.takeTells("itemString")');
  end
  
  if SD.table_items[itemString] and not SD.table_items[itemString]["status"] then
    SD.table_items[itemString]["tells"] = {};
    tellsInProgress = itemString;
    UI.tellsWindow.title:SetText(SD.table_items[itemString]["displayName"]);
    UI.tellsWindow.titleBg:SetWidth((UI.tellsWindow.title:GetWidth() or 0) + 10);
    E.Trigger("TELLS_UPDATE");
    SendChatMessage(SD.table_items[itemString]["itemLink"].." 30", "RAID");
    UI.itemWindow.tellsButton:Disable();
  else
    U.debug("Item does not exist or is already in progress!", 1);
  end
end

--   === items.requestTakeTells() =============================================

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
    tellsInProgress = itemString;
    if (raidLeaderUnitID and UnitIsConnected(raidLeaderUnitID)) or (not IsInRaid() and PD.debugOn > 0) then
      -- Ask raid leader for permission to start item
      U.debug('Asking Raid leader "' .. raidLeader .. '" for permission to post item (' .. itemString .. ').', 1);
      F.sendMessage("WHISPER", raidLeader, false, "postRequest", itemString);
      -- Set request timer
      requestPending = true;
      C_Timer.After(PD.postRequestMaxWait, function()
        if requestPending then
          U.debug(PD.postRequestMaxWait .. " seconds have elapsed with no response from raid leader, posting item (" .. tellsInProgress .. ") anyway.", 1);
          F.items.takeTells(tellsInProgress);
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

-- === Tells Button visibility handler ========================================

E.Register("TELLSBUTTON_UPDATE", function()
	if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") or PD.debugOn > 0 then
		UI.itemWindow.tellsButton:Show();
	else
		UI.itemWindow.tellsButton:Hide();
	end
end)

-- === GUI Initiator ==========================================================

E.Register("PLAYER_LOGIN", function()
	createGUI();
	E.Trigger("TELLSBUTTON_UPDATE");
	
	-- Horrible kludge to fix tellsButton not anchoring correctly.
	C_Timer.After(1, function()
		UI.itemWindow.tellsButton:ClearAllPoints();
		UI.itemWindow.tellsButton:SetPoint("BOTTOM", UI.itemWindow.bidButton, "TOP");
	end);
end);

-- postRequest message handler ================================================

M.Register("postRequest", function(channel, sender, requestedItem)
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

M.Register("postReply", function(_, _, allowed)
  if tellsInProgress and requestPending then
    if allowed then
      U.debug('Request to post item "' .. tellsInProgress .. '" has been granted. Posting...', 1);
      F.items.takeTells(tellsInProgress);
    else
      U.debug('Request to post item "' .. tellsInProgress .. '" has been denied. Item abandoned.', 1);
      -- cancel the item in progress
      tellsInProgress = nil;
      -- force a button state update
      E.Trigger("TELLSBUTTON_UPDATE");
    end
    
    requestPending = nil;
  end
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