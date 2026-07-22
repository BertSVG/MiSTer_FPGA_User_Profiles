# MiSTer-FPGA-User-Profiles
Adds user profiles to the MiSTer FPGA Project. 

1) Place mister_profiles.sh inside /media/fat/Scripts/ on your MiSTer SD card.
2) Run mister_profiles.sh from the OSD menu.
3) First time: pick a name for whoever's saves are already on the system. This will grab the saves and RA login information and place them inside the new user profile.
4) To add more users: Create the new profile using the script, then enter that user's RA username & password into the retroachievements.cfg file located here /media/fat/profiles/<name>/.
5) Users will need to switch to their profile before launching games or they will overwrite other user's save files. Save games, save states, and which RA account is logged in — belong to that specific user until someone switches again.
6) It never hurts double check you have the right user logged in. Logging in while logged in doesn't cause any problems.
