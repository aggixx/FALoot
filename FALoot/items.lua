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
local C = A.commands;

-- Call Libraries
local ScrollingTable = LibStub("ScrollingTable");

-- Init some tables
SD.table_itemQuery = {};
SD.table_items = {};
SD.table_icons = {};

-- Init "items" functions subtable
F.items = {};

-- Init some item window variables
local itemWindowSelection = nil;
local bidAmount = nil;

-- Init mob loot blacklist
local hasBeenLooted = {};

SD.difficultyBonusIDs = {
  [566] = true, -- heroic
  [567] = true, -- mythic
  [450] = true, -- mythic 2???
};

--[[ ==========================================================================
     GUI Creation
     ========================================================================== --]]
         
local function createGUI()
  UI.itemWindow = {};

  -- Create the main frame
  local frame = CreateFrame("frame", "FALootFrame", UIParent)
  frame:EnableMouse(true);
  frame:SetMovable(true);
  frame:SetMovable(true);
  frame:SetFrameStrata("FULLSCREEN_DIALOG");
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  });
  frame:SetBackdropColor(0, 0, 0, 1);
  frame:SetToplevel(true);
  frame:SetWidth(500);
  frame:SetHeight(270);
  frame:SetPoint("CENTER");
  frame:Hide();
  frame:SetScript("OnShow", function()
    E.Trigger("ITEM_UPDATE");
  end);
  
  UI.itemWindow.frame = frame;

  -- Create the frame that holds the icons
  local iconFrame = CreateFrame("frame", frame:GetName().."IconFrame", frame);
  iconFrame:SetHeight(40);
  iconFrame:SetWidth(500);
  iconFrame:SetPoint("TOP", frame, "TOP", 0, -30);
  iconFrame:Show();
  
  UI.itemWindow.iconFrame = iconFrame;
  
  -- Populate the iconFrame with icons
  for i=1,PD.maxIcons do
    SD.table_icons[i] = CreateFrame("frame", iconFrame:GetName().."Icon"..tostring(i), iconFrame)
    SD.table_icons[i]:SetWidth(40)
    SD.table_icons[i]:SetHeight(40)
    SD.table_icons[i]:Hide()
  end

  -- Create the scrollingTable
  local scrollingTable = ScrollingTable:CreateST({
    {
      ["name"] = "Item",
      ["width"] = 200,
      ["align"] = "LEFT",
      ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
      ["defaultsort"] = "asc",
    },
    {
      ["name"] = "Prop.",
      ["width"] = 30,
      ["align"] = "LEFT",
      ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
      ["defaultsort"] = "asc",
    },
    {
      ["name"] = "Status",
      ["width"] = 60,
      ["align"] = "LEFT",
      ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
      ["defaultsort"] = "dsc",
    },
    {
      ["name"] = "Winner(s)",
      ["width"] = 117,
      ["align"] = "LEFT",
      ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
      ["defaultsort"] = "dsc",
    }
  }, 8, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, frame);
  scrollingTable:EnableSelection(true);
  scrollingTable.frame:SetPoint("TOP", iconFrame, "BOTTOM", 0, -20);
  scrollingTable.frame:SetScale(1.1);
  
  -- Setup onclick to trigger an ITEMWINDOW_SELECT_UPDATE event
  scrollingTable:RegisterEvents({
    ["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, scrollingTable, ...)
      -- if the user clicked on a content cell
      if row and realrow then
        -- if the row clicked is already the one selected
        if scrollingTable:GetSelection() == realrow then
          -- then deselect the row
          scrollingTable:ClearSelection();
          -- then trigger an event
          E.Trigger("ITEMWINDOW_SELECT_UPDATE");
        else
          -- else select the row
          scrollingTable:SetSelection(realrow);
          
          -- determine then item's id
          local j = 0;
          local item;
          for i, v in pairs(SD.table_items) do
            j = j + 1;
            if j == realrow then
              item = i;
              break;
            end
          end
          U.debug("Clicked: "..item..", "..SD.table_items[item]["itemLink"], 2);
          
          -- then trigger an event
          E.Trigger("ITEMWINDOW_SELECT_UPDATE", item);
        end
        
        -- and override the default handler
        return true;
      end
    end,
  });
  
  UI.itemWindow.scrollingTable = scrollingTable;

  -- Create the "Close" button
  local closeButton = CreateFrame("Button", frame:GetName().."CloseButton", frame, "UIPanelButtonTemplate")
  closeButton:SetPoint("BOTTOMRIGHT", -27, 17)
  closeButton:SetHeight(20)
  closeButton:SetWidth(80)
  closeButton:SetText(CLOSE)
  closeButton:SetScript("OnClick", function(self)
    self:GetParent():Hide();
  end);
  
  UI.itemWindow.closeButton = closeButton;
  
  -- Create the "Bid" button
  local bidButton = CreateFrame("Button", frame:GetName().."BidButton", frame, "UIPanelButtonTemplate")
  bidButton:SetPoint("BOTTOMRIGHT", closeButton, "BOTTOMLEFT", -5, 0)
  bidButton:SetHeight(20)
  bidButton:SetWidth(80)
  bidButton:SetText("Bid")
  bidButton:SetScript("OnClick", function(self, event)
    local id = scrollingTable:GetSelection()
    local j, itemLink, itemString = 0;
    for i, v in pairs(SD.table_items) do
      j = j + 1;
      if j == id then
        itemLink, itemString = v["itemLink"], i;
        break;
      end
    end
    bidPrompt = coroutine.create(function(self)
      U.debug("Bid recieved, resuming coroutine.", 1)
      local bid = bidAmount;
      if bid < 30 and bid ~= 10 and bid ~= 20 then
        U.debug("You must bid 10, 20, 30, or a value greater than 30. Your bid has been cancelled.")
        return
      end
      if bid % 2 ~= 0 then
        bid = math.floor(bid)
        if bid % 2 == 1 then
          bid = bid - 1
        end
        U.debug("You are not allowed to bid odd numbers or non-integers. Your bid has been rounded down to the nearest even integer.")
      end
      F.items.bid(itemString, bid);
    end)
    StaticPopupDialogs["FALOOT_BID"]["text"] = "How much would you like to bid for "..itemLink.."?";
    StaticPopup_Show("FALOOT_BID");
    U.debug("Querying for bid, coroutine paused.", 1);
  end);
  bidButton:Disable();
  
  UI.itemWindow.bidButton = bidButton;

  -- Create the background of the Status Bar
  local statusbg = CreateFrame("Button", frame:GetName().."StatusBar", frame)
  statusbg:SetPoint("BOTTOMLEFT", 15, 15)
  statusbg:SetPoint("BOTTOMRIGHT", -197, 15)
  statusbg:SetHeight(24)
  statusbg:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 }
  })
  statusbg:SetBackdropColor(0.1,0.1,0.1)
  statusbg:SetBackdropBorderColor(0.4,0.4,0.4)

  -- Create the text of the Status Bar
  local statusText = statusbg:CreateFontString(statusbg:GetName().."Text", "OVERLAY", "GameFontNormal")
  statusText:SetPoint("TOPLEFT", 7, -2)
  statusText:SetPoint("BOTTOMRIGHT", -7, 2)
  statusText:SetHeight(20)
  statusText:SetJustifyH("LEFT")
  statusText:SetText("")
  
  UI.itemWindow.status = statusText;

  -- Create the background of the title
  local titlebg = frame:CreateTexture(frame:GetName().."TitleBackground", "OVERLAY")
  titlebg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  titlebg:SetTexCoord(0.31, 0.67, 0, 0.63)
  titlebg:SetPoint("TOP", 0, 12)
  titlebg:SetHeight(40)

  -- Create the title frame
  local title = CreateFrame("Frame", frame:GetName().."TitleMover", frame)
  title:EnableMouse(true)
  title:SetScript("OnMouseDown", function(frame)
    frame:GetParent():StartMoving()
  end)
  title:SetScript("OnMouseUp", function(frame)
    frame:GetParent():StopMovingOrSizing()
  end)
  title:SetAllPoints(titlebg)

  -- Create the text of the title
  local titletext = title:CreateFontString(frame:GetName().."TitleText", "OVERLAY", "GameFontNormal")
  titletext:SetPoint("TOP", titlebg, "TOP", 0, -14)
  titletext:SetText("FA Loot");
  
  titlebg:SetWidth((titletext:GetWidth() or 0) + 10)

  -- Create the title background left edge
  local titlebg_l = frame:CreateTexture(frame:GetName().."TitleEdgeLeft", "OVERLAY")
  titlebg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  titlebg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
  titlebg_l:SetPoint("RIGHT", titlebg, "LEFT")
  titlebg_l:SetWidth(30)
  titlebg_l:SetHeight(40)

  -- Create the title background right edge
  local titlebg_r = frame:CreateTexture(frame:GetName().."TitleEdgeRight", "OVERLAY")
  titlebg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  titlebg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
  titlebg_r:SetPoint("LEFT", titlebg, "RIGHT")
  titlebg_r:SetWidth(30)
  titlebg_r:SetHeight(40)
end

local function setStatus()
  local bidding, rolling, only = 0, 0;
  for itemString, v in pairs(SD.table_items) do
    if SD.table_items[itemString]["bidStatus"] and SD.table_items[itemString]["status"] ~= "Ended" then
      only = itemString;
      if SD.table_items[itemString]["bidStatus"] == "Bid" then
        bidding = bidding + 1;
      elseif SD.table_items[itemString]["bidStatus"] == "Roll" then
        rolling = rolling + 1;
      end
    end
  end
  
  if bidding + rolling == 0 then
    UI.itemWindow.status:SetText("");
  elseif bidding + rolling == 1 then
    local verb = "";
    if bidding > 0 then
      verb = "bid"
    else
      verb = "roll"
    end
    UI.itemWindow.status:SetText("Waiting to " .. verb .. " on " .. SD.table_items[only]["displayName"] .. ".")
  else
    if bidding > 0 and rolling > 0 then
      local plural1, plural2 = "", "";
      if bidding > 1 then
        plural1 = "s";
      end
      if rolling > 1 then
        plural2 = "s";
      end
      UI.itemWindow.status:SetText("Waiting to bid on " .. bidding .. " item" .. plural1 .. " and roll on " .. rolling .. " item" .. plural2 .. ".");
    elseif bidding > 0 then
      UI.itemWindow.status:SetText("Waiting to bid on " .. bidding .. " items.");
    else
      UI.itemWindow.status:SetText("Waiting to roll on " .. rolling .. " items.");
    end
  end
end

--[[ ==========================================================================
     Helper Functions
     ========================================================================== --]]

local function generateIcons()
  local lasticon = nil -- reference value for anchoring to the most recently constructed icon
  local firsticon = nil -- reference value for anchoring the first constructed icon
  local k = 0 -- this variable contains the number of the icon we're currently constructing, necessary because we need to be able to create multiple icons per entry in the table
  
  -- loop through the table of icons and reset everything
  for i=1,PD.maxIcons do
    SD.table_icons[i]:Hide()
    SD.table_icons[i]:ClearAllPoints()
    SD.table_icons[i]:SetBackdrop({
        bgFile = nil,
    })
    SD.table_icons[i]:SetScript("OnEnter", nil)
    SD.table_icons[i]:SetScript("OnLeave", nil)
  end
  
  -- loop through each row of data
  for i, v in pairs(SD.table_items) do
    for j=1,v["quantity"] do
      -- if we're constructing an icon number that's higher than what we're setup to display then just skip it
      if k < #SD.table_icons then
        -- increment k by 1 before starting to construct
        k = k + 1
        
        -- set the texture of the icon
        SD.table_icons[k]:SetBackdrop({ 
          bgFile = v["texture"],
        })
        
        -- set the icon's scripts
        SD.table_icons[k]:SetScript("OnEnter", function(self, button)
          -- store what row was selected so we can restore it later
          itemWindowSelection = UI.itemWindow.scrollingTable:GetSelection() or 0;
          
          -- retrieve the row id that corresponds to the icon we're mousedover
          local row = 0;
          for l, w in pairs(SD.table_items) do
            row = row + 1;
            if i == l then
              -- select the row that correlates to the icon
              UI.itemWindow.scrollingTable:SetSelection(row);
              break;
            end
          end
          
          --tooltip stuff
          GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(v["tooltipItemLink"])
	  F.history.setTooltip(i);
	  
          GameTooltip:Show()
        end)
        
        SD.table_icons[k]:SetScript("OnLeave", function(self, button)
          -- restore the row that was selected before we mousedover this icon
          UI.itemWindow.scrollingTable:SetSelection(itemWindowSelection);
          itemWindowSelection = nil;
          
          GameTooltip:Hide();
        end)
        
        SD.table_icons[k]:SetScript("OnMouseUp", function(self, button)
          if button == "LeftButton" then -- left click: Selects the clicked row
            if IsModifiedClick("CHATLINK") then
              ChatEdit_InsertLink(v["itemLink"])
            elseif IsModifiedClick("DRESSUP") then
              DressUpItemLink(v["itemLink"])
            else
              -- retrieve the row id that corresponds to the icon we're mousedover
              local row = 0;
              for l, w in pairs(SD.table_items) do
                row = row + 1;
                if i == l then
                  -- set iconSelect so that after the user finishes mousing over icons
                  -- the row corresponding to this one gets selected
                  itemWindowSelection = row;
                  E.Trigger("ITEMWINDOW_SELECT_UPDATE", l);
                  break;
                end
              end
            end
          elseif button == "RightButton" then -- right click: Ends the item, for everyone in raid if you have assist, otherwise only locally.
            endPrompt = coroutine.create( function()
              U.debug("Ending item "..v["itemLink"]..".", 1);
              if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
                F.sendMessage("RAID", nil, true, "end", i);
              end
              F.items.finish(i);
            end)
            if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
              StaticPopupDialogs["FALOOT_END"]["text"] = "Are you sure you want to manually end "..v["itemLink"].." for all players in the raid?";
            else
              StaticPopupDialogs["FALOOT_END"]["text"] = "Are you sure you want to manually end "..v["itemLink"].."?";
            end
            StaticPopup_Show("FALOOT_END");
          end
        end)
        
        -- if this isn't the first icon then anchor it to the previous icon
        if lasticon then
          SD.table_icons[k]:SetPoint("LEFT", lasticon, "RIGHT", 1, 0)
        end
        -- show the icon we just constructed
        SD.table_icons[k]:Show() 
        -- set the icon we just constructed as the most recently constructed icon
        lasticon = SD.table_icons[k];
      end
    end
  end
  
  -- anchor the first icon in the row so that the row is centered in the window
  SD.table_icons[1]:SetPoint("LEFT", UI.itemWindow.iconFrame, "LEFT", (501-(k*(40+1)))/2, 0)
end

--[[ ==========================================================================
  Static Popup Dialogs
     ========================================================================== --]]

StaticPopupDialogs["FALOOT_BID"] = {
  text = "How much would you like to bid?",
  button1 = "Bid",
  button2 = CANCEL,
  timeout = 0,
  whileDead = true,
  OnAccept = function(self)
    bidAmount = tonumber(self.editBox:GetText());
    coroutine.resume(bidPrompt);
  end,
  OnShow = function(self)
    self.editBox:SetText("");
    self.editBox:SetNumeric(true);
    self.editBox:SetScript("OnEnterPressed", function(self)
      bidAmount = tonumber(self:GetText());
      coroutine.resume(bidPrompt);
      StaticPopup_Hide("FALOOT_BID");
    end);
    self.editBox:SetScript("OnEscapePressed", function(self)
      StaticPopup_Hide("FALOOT_BID");
    end);
  end,
  hasEditBox = true,
  preferredIndex = STATICPOPUPS_NUMDIALOGS,
}

StaticPopupDialogs["FALOOT_END"] = {
  text = "Are you sure you want to manually end this item for all players in the raid?",
  button1 = YES,
  button2 = CANCEL,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  OnAccept = function()
    coroutine.resume(endPrompt)
  end,
  enterClicksFirstButton = 1,
  preferredIndex = STATICPOPUPS_NUMDIALOGS,
}

--[[ ==========================================================================
     Item Functions
     ========================================================================== --]]

--   === items.add() ==========================================================
     
F.items.add = function(itemString, checkCache)
  U.debug("itemAdd(), itemString = "..itemString, 1);
  -- itemString must be a string!
  if type(itemString) ~= "string" then
    U.debug("itemAdd was passed a non-string value!", 1);
    return;
  end
  
  local itemLink = U.ItemLinkAssemble(itemString);
  
  -- caching stuff
  if itemLink then
    U.debug("Item is cached, continuing.", 1);
    for i=1,#SD.table_itemQuery do
      if SD.table_itemQuery[i] == itemString then
        table.remove(SD.table_itemQuery, i)
        break
      end
    end
  else
    if not checkCache then
      U.debug("Item is not cached, requesting item info from server.", 1);
      table.insert(SD.table_itemQuery, itemString);
    else
      U.debug("Item is not cached, aborting.", 1);
    end
    return;
  end
  
  -- check if item passes the filter
  if not U.checkFilters(itemString, true) then
    U.debug(itemString.." did not pass the item filter.", 2);
    return;
  end
  
  if SD.table_items[itemString] then
    SD.table_items[itemString]["quantity"] = SD.table_items[itemString]["quantity"] + 1;
    local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
    local displayName = itemLink
    if SD.table_items[itemString]["quantity"] > 1 then
      displayName = displayName .. " x" .. SD.table_items[itemString]["quantity"];
    end
    SD.table_items[itemString]["displayName"] = displayName;
  else
    local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
    local displayName = itemLink
    SD.table_items[itemString] = {
      ["quantity"] = 1,
      ["displayName"] = displayName,
      ["itemLink"] = itemLink,
      ["texture"] = texture,
      ["currentValue"] = 30,
      ["winners"] = {},
      ["tooltipItemLink"] = itemLink,
    }
    
    if SD.authedMissingItems and SD.authedMissingItems[itemString] then
      SD.table_items[itemString].host = SD.authedMissingItems[itemString];
      SD.authedMissingItems[itemString] = nil;
    end
  end
  
  if not UI.itemWindow.frame:IsShown() then
    if UnitAffectingCombat("PLAYER") then
      showAfterCombat = true
      U.debug(itemLink.." was found but the player is in combat.");
    else
      UI.itemWindow.frame:Show()
    end
  end
  
  --[[ Don't call ITEM_UPDATE here, leave that up to the place where
       this method is called from for efficiency's sake --]]
  
  return true
end

-- === items.bid() ============================================================

F.items.bid = function(itemString, bid)
  bid = tonumber(bid)
  U.debug("FALoot:itemBid("..itemString..", "..bid..")", 1)
  if not SD.table_items[itemString] then
    U.debug("Item not found! Aborting.", 1);
    return;
  end
  
  SD.table_items[itemString]["bid"] = bid;
  SD.table_items[itemString]["bidStatus"] = "Bid";
  U.debug("items.bid(): Queued bid for "..SD.table_items[itemString]["itemLink"]..".", 1);
  
  -- Process the new bid, triggering a status text refresh if necessary.
  if not F.items.processBids() then
    E.Trigger("ITEMWINDOW_STATUS_TEXT_UPDATE");
  end
end

-- === items.processBids() ====================================================

F.items.processBids = function()
  local needsRefresh = false;

  for itemString, v in pairs(SD.table_items) do
    if SD.table_items[itemString]["bidStatus"] and SD.table_items[itemString]["host"] and ((v["currentValue"] == 30 and v["bid"] >= 30) or v["currentValue"] == v["bid"]) then
      if v["bidStatus"] == "Bid" and v["status"] == "Tells" then
        SendChatMessage(tostring(v["bid"]), "WHISPER", nil, v["host"]);
        SD.table_items[itemString]["bidStatus"] = "Roll";
        U.debug("items.processBids(): Bid and queued roll for "..SD.table_items[itemString]["itemLink"]..".", 1);
	needsRefresh = true;
      elseif v["bidStatus"] == "Roll" and v["status"] == "Rolls" then
        F.items.roll(v["bid"]);
        SD.table_items[itemString]["bidStatus"] = nil;
        U.debug("items.processBids(): Rolled for "..SD.table_items[itemString]["itemLink"]..".", 1);
	needsRefresh = true;
      end
    end
  end
  
  if needsRefresh then
    E.Trigger("ITEMWINDOW_STATUS_TEXT_UPDATE");
  end
  
  return needsRefresh;
end

-- === items.finish() ============================================================

F.items.finish = function(itemString)
  if not type(itemString) == "string" then
    error('Usage: items.finish("itemString")');
  elseif not SD.table_items[itemString] then
    return;
  end
  
  SD.table_items[itemString]["status"] = "Ended";
  
  if SD.tellsInProgress and SD.tellsInProgress == itemString then
    SD.tellsInProgress = nil;
    UI.tellsWindow.frame:Hide();
  end
  
  if SD.authedMissingItems then
    SD.authedMissingItems[itemString] = nil;
  end
  
  C_Timer.After(PD.expTime, function()
    if SD.table_items[itemString] and SD.table_items[itemString]["status"] == "Ended" then
      SD.table_items[itemString] = nil;
      E.Trigger("ITEM_UPDATE");
    end
  end);
  
  E.Trigger("ITEM_UPDATE");
  E.Trigger("ITEMWINDOW_STATUS_TEXT_UPDATE");
end

-- === items.addWinner() ======================================================

F.items.addWinner = function(itemString, winner, bid)
	if not (itemString and winner and bid) then
		U.debug("Input not valid, aborting.", 1);
		return;
	elseif not SD.table_items[itemString] then
		U.debug(itemString.." is not a valid active item!", 1);
		return;
	end
		
	-- check if the player was the winner of the item
	if winner == SD.PLAYER_NAME then
		U.debug("The player won an item!", 1);
		LootWonAlertFrame_ShowAlert(SD.table_items[itemString]["itemLink"], 1, LOOT_ROLL_TYPE_NEED, bid.." DKP");
	end
	
	-- create a table entry for that pricepoint
	if not SD.table_items[itemString]["winners"][bid] then
		SD.table_items[itemString]["winners"][bid] = {};
	end
	
	-- insert this event into the winners table
	table.insert(SD.table_items[itemString]["winners"][bid], winner);
	
	-- if # of winners >= item quantity then auto end the item
	local numWinners = 0;
	for j, v in pairs(SD.table_items[itemString]["winners"]) do
		numWinners = numWinners + #v;
	end
	U.debug("numWinners = "..numWinners, 3);
	if numWinners >= SD.table_items[itemString]["quantity"] then
		F.items.finish(itemString);
	end
end

-- === items.roll() ===========================================================

F.items.roll = function(value)
	value = tonumber(value);
	
	if value % 1 ~= 0 then
		U.debug("You are not allowed to bid non-integers. Your bid has been rounded down to the nearest even integer.");
		value = math.floor(value);
		if value % 2 == 1 then
			value = value - 1;
		end
	elseif value % 2 ~= 0 then
		U.debug("You are not allowed to bid odd numbers. Your bid has been rounded down to the nearest even number.");
		value = value - (value % 2);
	end
	
	if value > 30 then
		RandomRoll((value-30)/2, ((value-30)/2)+30)
	elseif value == 30 or value == 20 or value == 10 then
		RandomRoll(1, value)
	else
		U.debug("Invalid roll value!")
	end
end

C.Register("roll", function(value)
	if not (value and type(tonumber(value)) == "number") then
		U.debug('Invalid arguments for "roll" command, the correct format is "/fa roll x", eg: "/fa roll 90".');
		return;
	end
	F.items.roll(value);
end, "x -- rolls on an item for x DKP.");

--[[ ==========================================================================
     FALoot Events
     ========================================================================== --]]

-- === GUI Initiator ==========================================================

E.Register("PLAYER_LOGIN", function()
	createGUI();
end);

-- === Status Bar Updater =====================================================

E.Register("ITEMWINDOW_STATUS_TEXT_UPDATE", setStatus);

-- === Item Table Updater =====================================================

E.Register("ITEM_UPDATE", function(itemString)
  local t = {};
  
  for i, v in pairs(SD.table_items) do
    -- create status string
    local statusString, statusColor = "", {["r"] = 1, ["g"] = 1, ["b"] = 1, ["a"] = 1};
    if v["status"] == "Ended" then
      statusString = v["status"];
      statusColor = {["r"] = 0.5, ["g"] = 0.5, ["b"] = 0.5, ["a"] = 1};
    elseif v["status"] == "Tells" then
      statusString = v["currentValue"].." ("..v["status"]..")";
      statusColor = {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 1}
    elseif v["status"] == "Rolls" then
      statusString = v["currentValue"].." ("..v["status"]..")";
      statusColor = {["r"] = 1, ["g"] = 0, ["b"] = 0, ["a"] = 1};
    elseif not v["status"] or v["status"] == "" then
      statusString = v["currentValue"];
      statusColor = {["r"] = 0.5, ["g"] = 0.5, ["b"] = 0.5, ["a"] = 1};
    end
    
    -- create winner string
    local winnerString = "";
    for j, w in pairs(v["winners"]) do
      if winnerString ~= "" then
        winnerString = winnerString .. ", ";
      end
      local subString = "";
      for k=1,#w do
        if subString ~= "" then
          subString = subString .. " & ";
        end
        local shortName = w[k];
        -- Remove realm suffix for display
        if string.match(shortName, "^(.-)%-.+") then
          shortName = string.match(shortName, "^(.-)%-.+");
        end
        subString = subString .. shortName;
      end
      winnerString = winnerString .. subString .. " (" .. j .. ")";
    end
    
    -- create bonus string
    local bonusString = "";
    local numBonuses = 0;
    local bonuses = string.match(i, "%d+:%d+:([0-9:]+)");
    if bonuses then
      for bonus in string.gmatch(bonuses, "%d+") do
	if not SD.difficultyBonusIDs[tonumber(bonus)] then
	  numBonuses = numBonuses + 1;
	  bonusString = bonusString .. "+";
	end
      end
    end
    
    local bonusColor = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 };
    if numBonuses == 1 then
      bonusColor = { ["r"] = 0, ["g"] = 0.502, ["b"] = 1.0, ["a"] = 1.0 };
    elseif numBonuses == 2 then
      bonusColor = { ["r"] = 0.69, ["g"] = 0.282, ["b"] = 0.973, ["a"] = 1.0 };
    elseif numBonuses > 2 then
      bonusColor = { ["r"] = 1.0, ["g"] = 0.502, ["b"] = 0, ["a"] = 1.0 };
    end
    
    -- insert assembled data into table
    table.insert(t, {
      ["cols"] = {
        {
          ["value"] = v["displayName"],
          ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
        },
        {
          ["value"] = bonusString,
          ["color"] = bonusColor,
        },
        {
          ["value"] = statusString,
          ["color"] = statusColor,
        },
        {
          ["value"] = winnerString,
          ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
        },
      },
      ["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
    })
  end

  UI.itemWindow.scrollingTable:SetData(t, false);
  generateIcons();
  
  if UI.itemWindow.tellsButton then
    if #t >= 8 then
      UI.itemWindow.tellsButton:ClearAllPoints();
      UI.itemWindow.tellsButton:SetPoint("TOP", UI.itemWindow.bidButton, "BOTTOM");
    else
      UI.itemWindow.tellsButton:ClearAllPoints();
      UI.itemWindow.tellsButton:SetPoint("BOTTOM", UI.itemWindow.bidButton, "TOP");
    end
  end
  
  if SD.tellsInProgress and SD.tellsInProgress == itemString then
    E.Trigger("TELLSWINDOW_UPDATE");
  end
  F.items.processBids();
end);

-- === Item Select Reaction ===================================================

E.Register("ITEMWINDOW_SELECT_UPDATE", function(item)
  if item then
    if UI.itemWindow.tellsButton then
      if (not SD.table_items[item]["status"] or SD.table_items[item]["status"] == "") and not SD.tellsInProgress and not SD.pendingPostRequest then
        --U.debug("Status of entry #"..id..' is "'..(v["status"] or "")..'".', 1);
        UI.itemWindow.tellsButton:Enable();
      else
        UI.itemWindow.tellsButton:Disable();
      end
    end
    
    -- TODO: make this only enable if the item can be bid on
    UI.itemWindow.bidButton:Enable();
  else
    UI.itemWindow.tellsButton:Disable();
    UI.itemWindow.bidButton:Disable();
  end
end)

-- === Item End Msg Handler ===================================================

AM.Register("end", function(channel, sender, item)
  F.items.finish(item);
end);

-- === Loot Msg Handler =======================================================

AM.Register("loot", function(channel, sender, loot)
  if not A.isEnabled() then
    return;
  end

  -- check data integrity
  for i, v in pairs(loot) do
    if not (v["checkSum"] and v["checkSum"] == #v) then
      error("Loot data recieved via an addon message failed the integrity check.");
    end
  end

  for i, v in pairs(loot) do
    if not hasBeenLooted[i] then
      for j=1,#v do
        U.debug("Added "..v[j].." to the loot window via addon message.", 2);
        F.items.add(v[j]);
      end
      hasBeenLooted[i] = true;
    else
      U.debug(i.." has already been looted.", 2);
    end
  end

  E.Trigger("ITEM_UPDATE");
end);

-- Item Winner Msg handler ====================================================

AM.Register("itemWinner", function(channel, sender, itemString, winner, bid, cST)
  F.items.addWinner(itemString, winner, bid, cST);
end);

-- === Item Status handler ====================================================

CM.Register("RAID", function(sender, msg)
	local rank = 0;
	
	if PD.debugOn == 0 then
		for i=1,40 do
			local name, currentRank = U.GetRaidRosterInfo(i);
			if name == sender then
				rank = currentRank;
				break;
			end
		end
	end
	
	if not (PD.debugOn > 0 or rank > 0) then
		return;
	end
	
	local linkless, replaces = string.gsub(msg, SD.HYPERLINK_PATTERN, "");
	
	if replaces == 1 then -- if the number of item links in the message is exactly 1 then we should process it
		local itemLink = string.match(msg, SD.HYPERLINK_PATTERN); -- retrieve itemLink from the message
		local itemString = U.ItemLinkStrip(itemLink);
		msg = string.gsub(msg, "x%d+", ""); -- remove any "x2" or "x3"s from the string
		if not msg then
			return;
		end
		local value = string.match(msg, "]|h|r%s*(.+)"); -- take anything else after the link and any following spaces as the value
		if not value then
			return;
		end
		value = string.gsub(value, "%s+", " "); -- replace any double spaces with a single space
		if not value then
			return;
		end
		value = string.lower(value);
		
		if SD.table_items[itemString] then
			if not SD.table_items[itemString]["host"] then
				SD.table_items[itemString]["host"] = sender;
			end
			
			if string.match(value, "roll") then
				SD.table_items[itemString]["status"] = "Rolls";
			elseif string.match(value, "[321]0") then
				SD.table_items[itemString]["currentValue"] = tonumber(string.match(value, "[321]0"));
				SD.table_items[itemString]["status"] = "Tells";
			end
			
			E.Trigger("ITEM_UPDATE", itemString);
			--FALoot:checkBids(); --TODO
		else
			U.debug("Hyperlink is not in item table.", 2);
		end
	end
end);

-- === DE'd Item Ender ========================================================

CM.Register("CHANNEL", function(sender, msg, channel)
	if string.lower(channel) ~= "aspects" then
		return;
	end
	if not msg then
		return;
	end
	
	local itemLink = string.match(msg, SD.HYPERLINK_PATTERN);
	if not itemLink then
		return;
	end
	
	local itemString = U.ItemLinkStrip(itemLink);
	local msg = string.gsub(msg, SD.HYPERLINK_PATTERN, ""); -- now remove the link
	if not msg or msg == "" then
		return;
	end
	local msg = string.lower(msg) -- put in lower case
	local msg = " "..string.gsub(msg, "[/,]", " ").." "
	if string.match(msg, " d%s?e ") or string.match(msg, " disenchant ") then
		if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
			F.sendMessage("RAID", nil, true, "end", itemString);
		end
		F.items.finish(itemString);
	end
end);

--[[ ==========================================================================
     API Events
     ========================================================================== --]]

local eventFrame, events = CreateFrame("Frame"), {}

-- === Loot Comm Handler ======================================================

function events:LOOT_READY(...)
  if not A.isEnabled() then
    return;
  end
  
  local loot = {} -- create a temporary table to organize the loot on the mob
  
  for i=1,GetNumLootItems() do -- loop through all items in the window
    local sourceInfo = {GetLootSourceInfo(i)}
    for j=1,#sourceInfo/2 do
      local mobID = sourceInfo[j*2-1] -- retrieve GUID of the mob that holds the item
      if mobID and not hasBeenLooted[mobID] and not string.match(mobID, "^Item") then -- ignore items from sources that have already been looted or from item-based sources
        if not loot[mobID] then
          loot[mobID] = {};
        end
        local item = GetLootSlotLink(i);
        if item then
          local itemString = U.ItemLinkStrip(item);
          if itemString and U.checkFilters(itemString) then
            for l=1,max(sourceInfo[j*2], 1) do -- repeat the insert if there is multiple of the item in that slot.
              -- max() is there to remedy the bug with GetLootSourceInfo returning incorrect (0) values.
              -- GetLootSourceInfo may also return multiple quantity when there is actually only
              -- one of the item, but there's not much we can do about that.
              table.insert(loot[mobID], itemString);
            end
          end
        end
      end
    end
  end
  
  local empty = true;
  -- prune enemies with no loot
  for i, v in pairs(loot) do
    if #v == 0 then
      loot[i] = nil;
    else
      empty = false;
    end
  end
  
  -- stop now if there's no loot
  if empty then
    return;
  end
  
  -- add an item count for each GUID so that other clients may verify data integrity
  for i, v in pairs(loot) do
    loot[i]["checkSum"] = #v;
  end
  
  U.debug(loot, 3);
  
  -- check data integrity
  for i, v in pairs(loot) do
    if not (v["checkSum"] and v["checkSum"] == #v) then
      error("Self assembled loot data failed the integrity check.");
    end
  end
  
  -- send addon message to tell others to add this to their window
  F.sendMessage("RAID", nil, true, "loot", loot);
  
  for i, v in pairs(loot) do
    for j=1,#v do
      -- we can assume that everything in the table is not on the HBL
      F.items.add(v[j])
    end
    hasBeenLooted[i] = true;
  end
  
  E.Trigger("ITEM_UPDATE");
end

-- === Item Cache manager =====================================================

function events:GET_ITEM_INFO_RECEIVED()
  local limit, itemAdded = #SD.table_itemQuery;
  for i=limit,1,-1 do
    local result = F.items.add(SD.table_itemQuery[i], true);
    if result and not itemAdded then
      itemAdded = result;
    end
  end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end