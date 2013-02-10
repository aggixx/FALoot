**FA_RaidTools** is a loot and raid utility addon for \<Forgotten Aspects\> of Hyjal-US developed by Pawkets aka Fearmonger aka aggixx.

### How to Use ###
Click the **ZIP** button at the top of left of the page, save the zip file. Open the zip file with your favorite archiving program and extract the folder named "FARaidTools" (NOT FARaidTools-master) into the Interface/Addons/ folder in your WoW install.

**Important note**: The **version** of an addon is only read when you first start your WoW Client. It's a good idea to restart your client when updating to make sure that your client can access the correct version number for communications.

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
