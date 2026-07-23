# MiSTer-FPGA-User-Profiles

Adds user profiles to the MiSTer FPGA Project.

1. Either place [`mister_profiles.sh`](Scripts/mister_profiles.sh) inside `/media/fat/Scripts/` on your MiSTer SD card or add the following to `downloader.ini` on your SD card (or `/media/fat/downloader.ini`):

```ini
[BertSVG/MiSTer_FPGA_User_Profiles]
db_url = https://raw.githubusercontent.com/BertSVG/MiSTer_FPGA_User_Profiles/db/db.json.zip
```

2. Run `update.sh` or `update_all.sh` to install the script if you added it to `downloader.ini`.
3. Run `mister_profiles.sh` from the OSD menu.
4. First time: pick a name for whoever's saves are already on the system. This will grab the saves and RA login information and place them inside the new user profile.
5. To add more users: Create the new profile using the script, then enter that user's RA username & password into the retroachievements.cfg file located here /media/fat/profiles/<name>/.
6. Users will need to switch to their profile before launching games or they will overwrite other user's save files. Save games, save states, and which RA account is logged in — belong to that specific user until someone switches again.
7. It never hurts double check you have the right user logged in. Logging in while logged in doesn't cause any problems.
