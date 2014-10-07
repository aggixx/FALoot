local A = FALoot;
local SD = A.sData;

--[[ =======================================================
     Constant Definition
     ======================================================= --]]

SD.HYPERLINK_PATTERN = "\124c%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r";
-- |c COLOR    |H linkType : itemId : enchantId : gemId1 : gemId2 : gemId3 : gemId4 : suffixId : uniqueId  : linkLevel : reforgeId :      :      :      :      :      |h itemName            |h|r
-- |c %x+      |H item     : %d+    : %d+       : %d+    : %d+    : %d+    : %d+    : %-?%d+   : %-?%d+    : ?%d*      : ?%d*      : ?%d* : ?%d* : ?%d* : ?%d* : ?%d* |h .-                  |h|r"
-- |c ffa335ee |H item     : 94775  : 4875      : 4609   : 0      : 0      : 0      : 65197    : 904070771 : 89        : 166       : 465                              |h [Beady-Eye Bracers] |h|r"
-- |c ffa335ee |H item     : 96740  : 0         : 0      : 0      : 0      : 0      : 0        : 0         : 90        : 0         : 0                                |h[ Sign of the Bloodied God] |h|r 30
SD.THUNDERFORGED_COLOR = "FFFF8000";
SD.PLAYER_REALM = GetRealmName();
SD.PLAYER_NAME = UnitName("player") .. "-" .. SD.PLAYER_REALM;

SD.debugOn = 1;