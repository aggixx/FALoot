local A = FALoot;
local U = A.util;
local C = A.commands;
local AM = A.addonMessages;
local F = A.functions;
local PD = A.pData;

local function setAutoLoot()
	if not (PD.autolootToggle and PD.autolootKey) then
		return;
	end

	U.debug("Checking auto loot settings...", 2);
	local toggle, key = GetCVar("autoLootDefault"), GetModifiedClick("AUTOLOOTTOGGLE");
	
	if A.isEnabled(--[[true--]]) then
		if toggle ~= PD.autolootToggle or key ~= PD.autolootKey then
			-- Save current settings to be restored later
			PD.autolootToggle, PD.autolootKey = toggle, key;
		
			-- Apply new settings
			SetCVar("autoLootDefault", 0);
			SetModifiedClick("AUTOLOOTTOGGLE", "NONE");
			
			-- Notify user
			U.debug("Your autoloot has been disabled.");
		end
	else
		if toggle == "0" and key == "NONE" then
			-- Restore stored settings
			SetModifiedClick("AUTOLOOTTOGGLE", PD.autolootKey);
			SetCVar("autoLootDefault", PD.autolootToggle);
			
			-- Notify user
			U.debug("Your loot settings have been restored.");
		end
	end
end

F.setAutoLoot = setAutoLoot;

local frame = CreateFrame("frame");
frame:SetScript("OnEvent", setAutoLoot);
frame:RegisterEvent("VARIABLES_LOADED");
frame:RegisterEvent("GROUP_ROSTER_UPDATE");
frame:RegisterEvent("RAID_ROSTER_UPDATE");
