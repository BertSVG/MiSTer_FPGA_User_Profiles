#!/bin/bash
#
# mister_profiles.sh — per-user profiles for MiSTer FPGA
#
# This install script was coded with help from Claude AI
# but the method of implimenting user profiles was created, 
# tested, and implimented by humans before this script could be coded.
#
# Gives each person their own RetroAchievements login and their own save
# games / save states, by swapping three things per "profile":
#   - /media/fat/retroachievements.cfg   (a per-profile copy)
#   - /media/fat/saves                   (a symlink to a per-profile folder)
#   - /media/fat/savestates              (a symlink to a per-profile folder)
#
# IMPORTANT — read before using:
#   MiSTer itself has no concept of user accounts. RetroAchievements
#   support is not a stock MiSTer feature: it requires odelot's
#   RA-enabled fork of the main binary + modified cores, already
#   installed and working (see github.com/odelot/Main_MiSTer or
#   github.com/manyhats-mike/mister-fpga-retroachievements). This script
#   does NOT install RA support — it only manages multiple
#   retroachievements.cfg files and save folders for it, one active at
#   a time. Save states live in the same per-core save folders as save
#   games on most cores, so they move with the profile too.
#
# Install:
#   Copy this file to /media/fat/Scripts/mister_profiles.sh
#   Run it from the OSD: F12 -> Scripts -> mister_profiles
#
# Layout this script creates:
#   /media/fat/profiles/<name>/retroachievements.cfg
#   /media/fat/profiles/<name>/saves/<CORE>/...
#   /media/fat/profiles/<name>/savestates/<CORE>/...
#   /media/fat/profiles/.current              <- name of active profile
#   /media/fat/saves                          <- symlink to the active
#                                                 profile's saves folder
#   /media/fat/savestates                     <- symlink to the active
#                                                 profile's savestates folder
#   /media/fat/retroachievements.cfg          <- copy of the active
#                                                 profile's RA credentials

set -euo pipefail

BASE="/media/fat"
PROFILES_DIR="$BASE/profiles"
SAVES_LINK="$BASE/saves"
SAVESTATES_LINK="$BASE/savestates"
RA_CFG="$BASE/retroachievements.cfg"
CURRENT_FILE="$PROFILES_DIR/.current"

mkdir -p "$PROFILES_DIR"

# ---------- helpers ----------

pause() { echo; read -n 1 -s -r -p "Press any key to continue..."; echo; }

current_profile() {
    if [ -f "$CURRENT_FILE" ]; then
        cat "$CURRENT_FILE"
    else
        echo "(none)"
    fi
}

list_profiles() {
    find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# The first time this runs, /media/fat/saves and retroachievements.cfg
# are probably real files/folders, not yet managed by this script.
migrate_existing_into_profile() {
    local name="$1"
    local dir="$PROFILES_DIR/$name"
    mkdir -p "$dir/saves" "$dir/savestates"

    if [ -d "$SAVES_LINK" ] && [ ! -L "$SAVES_LINK" ]; then
        echo "Migrating existing saves into profile '$name'..."
        cp -a "$SAVES_LINK/." "$dir/saves/" 2>/dev/null || true
        rm -rf "$SAVES_LINK"
    fi

    if [ -d "$SAVESTATES_LINK" ] && [ ! -L "$SAVESTATES_LINK" ]; then
        echo "Migrating existing savestates into profile '$name'..."
        cp -a "$SAVESTATES_LINK/." "$dir/savestates/" 2>/dev/null || true
        rm -rf "$SAVESTATES_LINK"
    fi

    if [ -f "$RA_CFG" ] && [ ! -L "$RA_CFG" ]; then
        echo "Migrating existing retroachievements.cfg into profile '$name'..."
        cp -a "$RA_CFG" "$dir/retroachievements.cfg"
    fi
}

create_profile() {
    local name="$1"
    local dir="$PROFILES_DIR/$name"

    if [ -d "$dir" ]; then
        echo "Profile '$name' already exists."
        return 1
    fi

    mkdir -p "$dir/saves" "$dir/savestates"

    if [ -f "$BASE/retroachievements.cfg.template" ]; then
        cp "$BASE/retroachievements.cfg.template" "$dir/retroachievements.cfg"
    else
        cat > "$dir/retroachievements.cfg" <<'EOF'
# RetroAchievements configuration file

# RetroAchievements credentials
username=
password=

# Show popup when a challenge indicator appears (1=yes, 0=no)
show_challenge_show_popup=1

# Show popup when a challenge indicator disappears / is missed (1=yes, 0=no)
show_challenge_hide_popup=0

# Show popup for achievement progress updates (1=yes, 0=no)
show_progress_popups=1

# Include achievement name in progress popups (1=yes, 0=no)
show_progress_name=1

# Show leaderboard update popups (STARTED, FAILED, TRACKER SHOW/UPDATE) (1=yes, 0=no)
show_leaderboards_updates=1

# Show leaderboard submission popups (SUBMITTED and SCOREBOARD result) (1=yes, 0=no)
show_leaderboards_submission=1

# Turn on debug logging (1=yes, 0=no)
debug=0

# Enable hardcore mode for supported cores (1=yes, 0=no)
hardcore=0

# Force hardcore mode on unsupported cores (1=yes, 0=no)
force_hardcore=0

# Clear GBA IWRAM and EWRAM before each game load to prevent stale-RAM false
# positives in RetroAchievements (1=yes [default], 0=no)
gba_reset_ram=1

# Show achievement title and descriptions with two lines of text in the OSD (1=yes, 0=no)
multiline_desc=0

leaderboards-enabled=0
EOF
    fi

    echo "Created profile '$name' at $dir"
    echo "Edit $dir/retroachievements.cfg with that person's own"
    echo "RetroAchievements username/password before switching to it."
}

switch_profile() {
    local name="$1"
    local dir="$PROFILES_DIR/$name"

    if [ ! -d "$dir" ]; then
        echo "No such profile: $name"
        return 1
    fi

    if [ -L "$SAVES_LINK" ] || [ ! -e "$SAVES_LINK" ]; then
        rm -f "$SAVES_LINK"
    else
        echo "Refusing to touch $SAVES_LINK — it's a real directory, not"
        echo "a symlink managed by this script. Run 'Switch profile' once"
        echo "on a fresh profile first so it can migrate the data safely,"
        echo "or move $SAVES_LINK aside by hand."
        return 1
    fi
    ln -s "$dir/saves" "$SAVES_LINK"

    if [ -L "$SAVESTATES_LINK" ] || [ ! -e "$SAVESTATES_LINK" ]; then
        rm -f "$SAVESTATES_LINK"
    else
        echo "Refusing to touch $SAVESTATES_LINK — it's a real directory,"
        echo "not a symlink managed by this script. Run 'Switch profile'"
        echo "once on a fresh profile first so it can migrate the data"
        echo "safely, or move $SAVESTATES_LINK aside by hand."
        return 1
    fi
    ln -s "$dir/savestates" "$SAVESTATES_LINK"

    if [ -f "$dir/retroachievements.cfg" ]; then
        cp -a "$dir/retroachievements.cfg" "$RA_CFG"
    fi

    echo "$name" > "$CURRENT_FILE"

    echo "Switched to profile '$name'."
    echo "Saves      -> $dir/saves"
    echo "Savestates -> $dir/savestates"
    echo "RA cfg     -> $dir/retroachievements.cfg"
    echo
    echo "A reboot is recommended so the RA-enabled MiSTer binary re-reads"
    echo "the new credentials cleanly."
    read -n 1 -s -r -p "Reboot now? [y/N] " ans
    echo
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        reboot
    fi
}

# ---------- menu ----------

echo "=========================================="
echo " MiSTer User Profiles"
echo " Current profile: $(current_profile)"
echo "=========================================="
echo "1) List profiles"
echo "2) Create a new profile"
echo "3) Switch profile"
echo "4) Quit"
echo
read -p "Choose an option: " choice

case "$choice" in
    1)
        echo "Profiles:"
        list_profiles
        pause
        ;;
    2)
        read -p "New profile name (no spaces): " newname
        create_profile "$newname"
        pause
        ;;
    3)
        echo "Profiles:"
        list_profiles
        echo
        read -p "Profile to switch to (existing or new name): " target

        if { [ ! -L "$SAVES_LINK" ] && [ -d "$SAVES_LINK" ]; } || \
           { [ ! -L "$SAVESTATES_LINK" ] && [ -d "$SAVESTATES_LINK" ]; }; then
            migrate_existing_into_profile "$target"
        fi
        if [ ! -d "$PROFILES_DIR/$target" ]; then
            create_profile "$target"
        fi
        switch_profile "$target"
        pause
        ;;
    4)
        exit 0
        ;;
    *)
        echo "Invalid option."
        pause
        ;;
esac
