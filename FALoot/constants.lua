local A = FALoot;
local SD = A.sData;

--[[ =======================================================
     Constant Definition
     ======================================================= --]]

SD.HYPERLINK_PATTERN = "\124c%x+\124Hitem:%d+[-%d:]*\124h.-\124h\124r";
SD.THUNDERFORGED_COLOR = "FFFF8000";
SD.PLAYER_REALM = GetRealmName();
SD.PLAYER_NAME = UnitName("player") .. "-" .. SD.PLAYER_REALM;