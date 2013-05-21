**FA_RaidTools** is a loot and raid utility addon for \<Forgotten Aspects\> of Hyjal-US developed by Pawkets aka Fearmonger aka aggixx.

### How to Use (READ THIS!!!)###
Click the link below and save the zip file. Open the zip file with your favorite archiving program and extract the folder named "FARaidTools" (NOT FARaidTools-master) into the Interface/Addons/ folder in your WoW install.

Download here:
https://codeload.github.com/aggixx/FA_RaidTools/zip/master

Advanced users may instead choose to check out the repository directly into their addon folder using the following repository url:
https://github.com/aggixx/FA_RaidTools.git/trunk/FARaidTools

### In-game slash commands ###
**The following are valid commands for /rt**:
- **/rt** - shows the addon window
- **/rt debug <true/false>** - set status of debug mode
- **/rt who** - see who is running the addon and what version
- **/rt alias add <name>** - add an alias for award detection
- **/rt alias remove <name>** - remove an alias for award detection
- **/rt alias list** - list aliases for award detection
- **/rt resetpos** - resets the position of the RT window
- **Any command not listed above** - shows this list in-game.

### Upcoming Features ###
- Button that automates taking tells on an item. A fixed timer along with a addon command could be used so that others using the addon could see the progress of the item. Also potentially add a way for people to "stall" the timer of an item by request.
- Retroactively pull item values from aspects chat and pass them to others in the raid.
- Add the amount of DKP spent on the item to the LootAlert frame.
- Add item expiration time as an option.
- Customizable loot filters instead of hardcoded ones (potentially spec/class based).

### Known Bugs ###
- If you link a ton of items in one message and then send it it ends an item somehow. (needs checking)
- Pressing enter doesn't submit the bid amount form. (maybe not fixable?)
- Autoloot toggle being dumb again. (committed a fix, needs confirm)
- Items missing in window for the non-looter. (committed a fix, needs confirm)
