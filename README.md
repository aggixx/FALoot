**FA_RaidTools** is a loot and raid utility addon for \<Forgotten Aspects\> of Hyjal-US developed by Pawkets aka Fearmonger aka aggixx.

### How to Use ###
Put the folder named "FARaidTools" (NOT FARaidTools-master) into the Interface/Addons/ folder in your WoW install.

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
- Spec/class based gear filters on what shows up in the window
- Button that automates taking tells on an item. A fixed timer along with a addon command could be used so that others using the addon could see the progress of the item. Also potentially add a way for people to "stall" the timer of an item by request.
- Retroactively pull item values from aspects chat and pass them to others in the raid.
- Add the amount of DKP spent on the item to the LootAlert frame.
- Change text on mode button to be more clear.
- Shift click to link items, Ctrl click to view items.

### Known Bugs ###
- If you link a ton of items in one message and then send it it ends an item somehow. (needs checking)
- Pressing enter doesn't submit the bid amount form. (maybe not fixable?)
- Autoloot toggle being dumb again. (committed a fix, needs confirm)
