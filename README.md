# Infected
Infected gamemode for CS:GO

## Installation

To install, download the repository, then simply drag and drop its contents. You will need to upload the contents of `sounds` to your downloads server for sounds to work. By default, `infected-anticamp.smx` is enabled, this plugin prevents mass camping in a single spot. If you want to disable it, move it to `plugins/disabled`.

There is a sample `gamemode_casual_server.cfg` and `server.cfg` given. Feel free to change this how you want, if you change some options the plugin might not work as intended, though.

## Commands

- **!sound** or **!sounds** - Enables/disables the sound

### Admin

- **!spawns** - Brings up the spawns menu
- **!refreshweaponsets** - Reloads the weapon sets configuration

## Configuration

You can add/remove spawns for any map. To do so, type **!spawns** as an admin.

You can change the possible weapon sets by changing `configs/infected/weaponsets.txt`. The available weapons are at the top of the file. The format should be self explanatory.
