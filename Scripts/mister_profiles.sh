#!/bin/bash
#
# mister_profiles.sh — per-user profiles for MiSTer FPGA
# Version: 2.0.0
# Copyright (C) 2026  BertSVG
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Gives each person their own RetroAchievements login, their own save
# games / save states, and their own controller input mappings, by
# swapping four things per "profile":
#   - /media/fat/retroachievements.cfg   (a per-profile copy)
#   - /media/fat/saves                   (a symlink to a per-profile folder)
#   - /media/fat/savestates              (a symlink to a per-profile folder)
#   - /media/fat/config/inputs           (a symlink to a per-profile folder)
#
# IMPORTANT — read before using:
#   MiSTer itself has no concept of user accounts. RetroAchievements
#   support is not a stock MiSTer feature: it requires odelot's
#   RA-enabled fork of the main binary + modified cores, already
#   installed and working (see github.com/odelot/Main_MiSTer or
#   github.com/manyhats-mike/mister-fpga-retroachievements). This script
#   does NOT install RA support — it only manages multiple
#   retroachievements.cfg files, save folders, and save-state folders
#   for it, one profile active at a time.
#
# Install:
#   Copy this file to /media/fat/Scripts/mister_profiles.sh
#   chmod +x /media/fat/Scripts/mister_profiles.sh
#   Run it from the OSD: F12 -> Scripts -> mister_profiles
#
# Profile identity: each profile's folder is named by a stable, opaque
# ID (User001, User002, ...) that is allocated once and NEVER reused or
# changed — the display name typed in by the user lives in a separate
# ".name" file inside that folder. Renaming a profile only ever rewrites
# that one small file; the folder itself and every live symlink pointing
# at it are untouched. This matters: an earlier version used the display
# name itself as the folder name, so renaming meant moving the whole
# folder and re-pointing the live saves/savestates/inputs symlinks to
# match — and if those live paths weren't proper symlinks at that exact
# moment for any reason, the re-pointing step silently skipped itself
# while the rename still reported success, leaving gameplay writing into
# a path the renamed profile no longer tracked (a real data-loss bug,
# not hypothetical). With storage identity separated from the display
# name, there's nothing left to move and nothing that can get out of
# sync — renaming is just a one-line file write.
#
# Layout this script creates:
#   /media/fat/profiles/<id>/.name            <- display name (id is
#                                                 e.g. User001, User002)
#   /media/fat/profiles/<id>/retroachievements.cfg
#   /media/fat/profiles/<id>/saves/<CORE>/...
#   /media/fat/profiles/<id>/savestates/<CORE>/...
#   /media/fat/profiles/<id>/inputs/*.map
#   /media/fat/profiles/<id>/menu.png         <- optional, set via the
#                                                 "Set Wallpaper" menu
#   /media/fat/profiles/.current              <- id of the active profile
#   /media/fat/profiles/.next_id              <- counter for allocating
#                                                 the next User### id
#   /media/fat/profiles/.trash/<id>-<epoch>/  <- profiles removed via
#                                                 "Delete User", kept for
#                                                 TRASH_RETENTION_DAYS
#                                                 before being purged for
#                                                 good (0 = deleted
#                                                 immediately instead), or
#                                                 brought back early via
#                                                 "Restore User"
#   /media/fat/profiles/.trash_retention      <- saved "Trash Settings"
#                                                 choice, in days (0-30)
#   /media/fat/wallpapers/*.png               <- staging folder for
#                                                 "Set Wallpaper"; drop
#                                                 .png files in by hand
#                                                 (e.g. SFTP) first
#   /media/fat/saves                          <- symlink to the active
#                                                 profile's saves folder
#   /media/fat/savestates                     <- symlink to the active
#                                                 profile's savestates folder
#   /media/fat/config/inputs                  <- symlink to the active
#                                                 profile's inputs folder
#   /media/fat/retroachievements.cfg          <- copy of the active
#                                                 profile's RA credentials
#   /media/fat/menu.png                       <- copy of the active
#                                                 profile's wallpaper, if
#                                                 it has one (a reboot is
#                                                 needed for the OSD to
#                                                 pick up a new one)
#
# Code map (in file order):
#   Locale                     - best-effort UTF-8 locale selection (see
#                                 box_content_str's truncation)
#   Theme / terminal setup     - theme_on/theme_off, trap, load_theme,
#                                 THEME_NAMES/THEME_FG
#   General helpers            - msg_margin, msg, msg_handoff,
#                                 collect_handoff_messages, rep, sp
#   Box & frame drawing        - box_*, wrap_text, emit_line, blank_line,
#                                 monitor_frame, frame_done
#   Splash screen              - SPLASH_ART, show_splash
#   Input                      - read_key
#   Menus                      - draw_pending_messages, show_messages,
#                                 pause, select_menu, confirm_menu
#   Text entry                 - pad_center, mkrow, split_row, cell_label,
#                                 render_cell, redraw_cell, draw_grid,
#                                 text_entry (the on-screen keyboard —
#                                 the only way to enter text, no Type
#                                 Directly/On-Screen Keyboard chooser)
#   Profile state & operations - profile_name, profile_name_exists,
#                                 next_profile_id, current_profile(_id),
#                                 is_active_profile, list_profiles,
#                                 list_trash, prune_trash,
#                                 migrate_dir_into_profile, copy_if_exists,
#                                 create/switch_profile (incl. relink),
#                                 update_ra_credentials, prompt_ra_login
#   Manage Users screen        - get_new_profile_name, rename/copy/delete_user,
#                                 edit_ra_login, wallpaper_users,
#                                 set_wallpaper, restore_user,
#                                 pick_managed_user, manage_create_user,
#                                 manage_copy_user, manage_rename_user,
#                                 manage_edit_ra_login, manage_set_wallpaper,
#                                 manage_delete_user, manage_users_menu
#   Settings screen            - draw_menu_color_screen, menu_color_menu,
#                                 change_trash_retention, settings_menu
#   Select User screen         - select_user_menu
#   Main menu loop             - the bottom of the file

set -euo pipefail

BASE="/media/fat"
PROFILES_DIR="$BASE/profiles"
SAVES_LINK="$BASE/saves"
SAVESTATES_LINK="$BASE/savestates"
INPUTS_LINK="$BASE/config/inputs"
RA_CFG="$BASE/retroachievements.cfg"
MENU_PNG="$BASE/menu.png"
WALLPAPERS_DIR="$BASE/wallpapers"
CURRENT_FILE="$PROFILES_DIR/.current"
THEME_FILE="$PROFILES_DIR/.theme"
NEXT_ID_FILE="$PROFILES_DIR/.next_id"
TRASH_DIR="$PROFILES_DIR/.trash"
TRASH_RETENTION_FILE="$PROFILES_DIR/.trash_retention"

mkdir -p "$PROFILES_DIR" "$WALLPAPERS_DIR" "$TRASH_DIR"

# ---------- locale ----------
# Several status messages below use an em dash (—), a 3-byte UTF-8
# character. bash's own string length/slicing (${#var}, ${var:off:len} —
# used throughout box_content_str/wrap_text for box-width padding and
# truncation) only treats that as one unit under a UTF-8-aware locale;
# under a byte-based one (e.g. plain "C", and MiSTer's own locale isn't
# something this script can verify in advance) a fixed-width truncation
# can land in the middle of the character's bytes and print a corrupted
# character instead of just cleanly losing it. Best-effort only: picks
# whichever of these is actually installed, and does nothing (leaving
# whatever locale was already active) if neither is. wrap_text wrapping
# messages before they ever reach box_content_str (see there) already
# makes mid-word truncation rare in practice — this covers the rest.
# Tries both the hyphenated ("C.UTF-8") and glibc's own no-hyphen
# listing spelling ("C.utf8") — real systems vary on which one `locale -a`
# actually prints, and MiSTer's own C library isn't a known quantity here
# either (may not even have a "locale" command at all, in which case this
# loop harmlessly finds nothing and changes nothing).
for _mp_locale in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if locale -a 2>/dev/null | grep -qix "$_mp_locale"; then
        export LC_ALL="$_mp_locale"
        break
    fi
done
unset _mp_locale

# ---------- monochrome theme ----------
# Black background, single-color bright text, cursor hidden (it has
# nothing useful to show once we're drawing our own highlighted rows) for
# the whole session. Screen clears (\033[2J) don't reset any of this, so
# it only needs to be set once; theme_off restores normal terminal state
# on exit (including on error, via the trap) so the console isn't left
# colored with no cursor afterward.
#
# The color itself is one of the standard ANSI foreground colors, named
# by their actual standard names (not cute aliases like "Amber"). Black
# is excluded — it'd be invisible against the black background used
# below. MiSTer's console doesn't render 24-bit truecolor or 256-color
# indexed mode accurately — both confirmed on hardware to silently
# quantize down to these same 16 colors — so customization is limited to
# this fixed set rather than free-form/indexed color input.
#
# Two independent choices: which color (THEME_NAMES/THEME_INDEX) and
# which intensity tier, Bright (9X) or Dark (base, 3X) — THEME_TIER,
# both picked from the same combined Settings -> Menu Color screen (see
# menu_color_menu), under separate "Colors"/"Brightness" section labels.
# Every switch between codes goes through a full \033[0m
# reset first (see theme_on and box_line below) specifically because
# mixing tiers without resetting first once caused a real attribute-
# bleed bug on hardware (a base code inherited the previous bright
# color's intensity) — the fix is the same regardless of whether the
# mixing happens once at startup or every time a row is highlighted.
#
# Selection is shown with an actual colored background (THEME_BG) and
# black text, not the ">...<" bracket markers this script used before
# 2026-07-28. That earlier choice was made when colored backgrounds
# were thought to be broken under every mechanism tried — a
# photo-confirmed re-test (`Diaolog_Test.sh`) showed dark/base-tier
# backgrounds actually render cleanly, at least for some colors.
# Bright-tier backgrounds are still confirmed muddy/wrong, and Red/
# Blue/Magenta in dark tier were only reported as relatively harder to
# read, not individually photo-verified — this is offered as full
# open customization anyway (same "your choice, your results" spirit
# as the color choice itself always had), not a guarantee every
# combination looks equally good.
THEME_NAMES=(Green Yellow White Red Blue Magenta Cyan)
THEME_FG_BRIGHT=(92 93 97 91 94 95 96)
THEME_FG_DARK=(32 33 37 31 34 35 36)
THEME_BG_BRIGHT=(102 103 107 101 104 105 106)
THEME_BG_DARK=(42 43 47 41 44 45 46)
THEME_INDEX=0
THEME_TIER="dark"
THEME_TIER_FILE="$PROFILES_DIR/.theme_tier"

# A real ESC byte for building escape sequences into a variable that
# later gets passed through printf's %s (which does NOT itself
# interpret backslash escapes in its argument — only a format string
# printf receives directly does that). Plain "\033" typed inside a
# double-quoted string is just four literal characters, not the ESC
# byte; $'\033' (ANSI-C quoting) is what actually produces it — a real
# bug hit and fixed while building this feature's prototype
# (Diaolog_Test.sh).
ESC=$'\033'

# Current foreground/background ANSI code for whatever color+tier is
# active — every place that needs to color something goes through
# these instead of indexing THEME_FG_BRIGHT/DARK directly, so there's
# one place that knows how THEME_TIER maps to a real code.
current_theme_fg() {
    if [ "$THEME_TIER" = "bright" ]; then
        echo "${THEME_FG_BRIGHT[$THEME_INDEX]}"
    else
        echo "${THEME_FG_DARK[$THEME_INDEX]}"
    fi
}
current_theme_bg() {
    if [ "$THEME_TIER" = "bright" ]; then
        echo "${THEME_BG_BRIGHT[$THEME_INDEX]}"
    else
        echo "${THEME_BG_DARK[$THEME_INDEX]}"
    fi
}

load_theme() {
    local saved i
    [ -f "$THEME_FILE" ] || return 0
    saved=$(cat "$THEME_FILE")
    for i in "${!THEME_NAMES[@]}"; do
        if [ "${THEME_NAMES[$i]}" = "$saved" ]; then
            THEME_INDEX=$i
            return
        fi
    done
}

load_theme_tier() {
    local saved
    [ -f "$THEME_TIER_FILE" ] || return 0
    saved=$(cat "$THEME_TIER_FILE")
    if [ "$saved" = "bright" ] || [ "$saved" = "dark" ]; then
        THEME_TIER="$saved"
    fi
}

# How long a removed profile sits in TRASH_DIR (see delete_user/prune_trash
# below) before being purged for good — user-configurable via "Trash
# Retention" on the main menu (change_trash_retention), persisted the same
# way as the color theme. 0 is a real option, not a missing/error value —
# it means "skip the trash entirely, delete immediately" (the old
# behavior, for anyone who'd rather not have removed profiles linger on
# the SD card at all). Defaults to 1 day until load_trash_retention
# overrides it from a saved value.
TRASH_RETENTION_OPTIONS=(0 1 3 7 14 30)
TRASH_RETENTION_DAYS=1

load_trash_retention() {
    local saved
    [ -f "$TRASH_RETENTION_FILE" ] || return 0
    saved=$(cat "$TRASH_RETENTION_FILE")
    # Real if-block, not a bare "[ cond ] && assign" — this is the last
    # statement in the function, and the function is called bare at
    # startup, so a corrupted/non-numeric saved value failing the regex
    # would otherwise abort the whole script before it ever shows the
    # menu (same set -e hazard as prune_trash/delete_user; see CLAUDE.md).
    if [[ "$saved" =~ ^[0-9]+$ ]]; then
        TRASH_RETENTION_DAYS="$saved"
    fi
}

# \033[0m first is required, not cosmetic: switching color codes without
# resetting first left the old color's intensity attribute bleeding into
# the new one on hardware (seen when THEME_FG mixed base and bright
# codes — a base code inherited the previous bright color's intensity).
# Reset clears that before the new background/foreground are applied.
theme_on() { printf '\033[0m\033[40m\033[%sm\033[2J\033[H\033[?25l' "$(current_theme_fg)"; }
theme_off() { printf '\033[0m\033[2J\033[H\033[?25h'; }
trap theme_off EXIT

load_theme
load_theme_tier
load_trash_retention

theme_on

# ---------- general helpers ----------

# Left margin for anything printed outside a monitor_frame box
# (confirm_menu, pause, and the boxed message block the various switch/
# rename/copy/remove/etc. status messages now render as) — without this
# it lands flush at column 1 while every boxed screen (select_menu,
# text_entry) is centered, which reads as broken once the boxes started
# centering themselves. Queries the real terminal width fresh every call
# — same plain `stty size` monitor_frame uses — so this adapts if the
# resolution changes mid-session too, rather than being computed once
# and going stale.
#
# Emits a cursor-forward escape (`\033[nC`), NOT n literal space
# characters — a real, hardware-reported bug: printing actual spaces
# here doesn't just move where the following text starts, it overwrites
# whatever was already sitting in those columns with blanks, which wiped
# out the left half of the decorative side art (columns well within this
# margin) every time a message/confirm prompt was drawn over it (the
# right side art, past this margin's reach, was untouched — that
# asymmetry was the tell). `\033[nC` moves the cursor the same distance
# without touching a single character underneath it.
msg_margin() {
    local cols=240 size assumed_width=44 col
    if size=$(stty size 2>/dev/null); then
        cols=${size#* }
    fi
    col=$(( (cols - assumed_width) / 2 ))
    [ "$col" -le 0 ] && return
    printf '\033[%dC' "$col"
}

# Queues $1 for the next flush (see MSG_BUFFER, draw_pending_messages)
# instead of printing it immediately — a whole run of msg calls between
# one flush and the next renders together as one bordered block (same
# nested-box look confirm_menu uses) rather than as bare scrolling text.
# This used to be two functions (msg/msg_err, the latter writing to
# stderr specifically so a message didn't corrupt a caller's command
# substitution) — queuing into a plain array touches no file descriptor
# at all regardless of which one was called, so that distinction no
# longer means anything and the two were merged. An empty string is a
# valid call (see switch_profile's blank separator line between its
# saves/savestates table and the RA-username line) — it just becomes a
# blank row within the block.
#
# NOT safe to use from inside a function that is itself invoked via
# command substitution and doesn't call pause()/confirm_menu before
# returning (e.g. `newid=$(create_profile ...)`) — command substitution
# is a subshell, and appending to MSG_BUFFER there only ever mutates
# that subshell's own copy, which is discarded the moment it exits,
# before the outer script's real MSG_BUFFER ever sees the append (the
# same fact that bit FRAME_ROW/FRAME_COL earlier — see CLAUDE.md).
# get_new_profile_name gets away with using plain msg because it calls
# pause() itself in that same subshell before returning, so its message
# is fully displayed and cleared before the subshell exits — create_profile
# has no such opportunity (its whole job is handing back an ID with no UI
# interaction of its own), so it uses msg_handoff instead; see below.
msg() { MSG_BUFFER+=("$1"); }

# Appends $1 to MSG_HANDOFF_FILE instead of MSG_BUFFER — a plain file,
# unlike a shell array, survives past the command substitution subshell
# create_profile (and migrate_dir_into_profile, which it calls) always
# runs inside. See msg's own comment above for why this is necessary.
msg_handoff() {
    printf '%s\n' "$1" >> "$MSG_HANDOFF_FILE"
}

# Reads back anything queued via msg_handoff (if any) into MSG_BUFFER,
# in order, then removes the handoff file — call this immediately after
# `x=$(create_profile ...)` so those messages join the normal flush
# mechanism (draw_pending_messages) like everything else's.
collect_handoff_messages() {
    [ -f "$MSG_HANDOFF_FILE" ] || return 0
    local line
    while IFS= read -r line; do
        MSG_BUFFER+=("$line")
    done < "$MSG_HANDOFF_FILE"
    rm -f "$MSG_HANDOFF_FILE"
}

# ---------- box & frame drawing ----------

# Widest of the given strings, plus room for borders (1 char) each side
# and the widest possible box_line margin — 3-space indent + ">" + "<"
# (5 chars) for a highlighted row — so even the longest item never gets
# clipped when it's the selected one.
box_width_for() {
    local max=0 s len
    for s in "$@"; do
        len=${#s}
        [ "$len" -gt "$max" ] && max=$len
    done
    echo $((max + 7))
}

# Greedily word-wraps $2 into lines of at most $1 characters, breaking
# only on whitespace (never mid-word) — echoes one wrapped line per
# output line, for the caller to capture via mapfile. Used by
# confirm_menu so a long prompt stays fully readable inside a
# fixed-width box instead of forcing the box wider than its intended
# size (see confirm_menu's own note on why its box width is fixed, not
# prompt-driven). A single word longer than the width is left as its own
# (over-length) line rather than split — box_line already truncates
# safely if that line still doesn't fit, so this never breaks the box
# itself, just that one word's display.
wrap_text() {
    local width="$1" text="$2" word line=""
    for word in $text; do
        if [ -z "$line" ]; then
            line="$word"
        elif [ $(( ${#line} + 1 + ${#word} )) -le "$width" ]; then
            line="$line $word"
        else
            echo "$line"
            line="$word"
        fi
    done
    [ -n "$line" ] && echo "$line"
}

# n copies of a character / n plain spaces — used by both the box helpers
# below and the monitor-frame art. rep avoids forking `tr` (pure bash
# pattern substitution instead) since it's called on every redraw of
# every box border.
rep() { local n="$1" c="$2" s; [ "$n" -le 0 ] && return; printf -v s '%*s' "$n" ''; printf '%s' "${s// /$c}"; }
sp()  { local n="$1"; [ "$n" -le 0 ] && return; printf '%*s' "$n" ''; }

# All box-drawing helpers go through this. Normally it just prefixes a line
# with PAD_LEFT (plain left-indent, e.g. confirm_menu — usually empty).
# When CURSOR_ROW is set (select_menu drawing inside monitor_frame's
# rectangle), it instead positions the cursor absolutely at (CURSOR_ROW,
# CURSOR_COL) and advances CURSOR_ROW — needed because a plain trailing \n
# resets to column 1, not back to the indented frame column.
PAD_LEFT=""
CURSOR_ROW=""
CURSOR_COL=""

# Row monitor_frame's top-left corner actually landed on — usually 1,
# but centering (see monitor_frame) can push it further in. frame_done
# needs this to know where "just below the frame" is. Safe to rely on
# across a monitor_frame call and a later frame_done call in the same
# function invocation (they always run in the same subshell there) —
# NOT safe to read from some other, later top-level call: every real
# call site invokes select_menu etc. as `x=$(select_menu ...)`, and
# command substitution is a subshell, so whatever it sets here never
# survives back out once it returns (learned the hard way — see
# CLAUDE.md's side-art notes).
FRAME_ROW=1

# Queued status-message lines (see msg) — msg no longer prints
# immediately; it just appends here, so whatever accumulates between one
# flush and the next renders as a single bordered block instead of bare
# scrolling text. Flushed (and cleared) by whichever of pause() or
# confirm_menu happens to run next — see draw_pending_messages.
MSG_BUFFER=()

# See msg_handoff/collect_handoff_messages below — a plain file, not a
# shell variable, so a message can survive being queued from inside a
# command substitution subshell (e.g. `newid=$(create_profile ...)`).
# Removed at startup in case a prior run crashed before collecting it,
# so a stale message from a previous session can never resurface.
MSG_HANDOFF_FILE="/tmp/mister_profiles_msg_handoff"
rm -f "$MSG_HANDOFF_FILE"

emit_line() {
    local text="$1"
    if [ -n "$CURSOR_ROW" ]; then
        printf '\033[%d;%dH%s' "$CURSOR_ROW" "$CURSOR_COL" "$text" >&2
        CURSOR_ROW=$((CURSOR_ROW + 1))
    else
        printf '%s%s\n' "$PAD_LEFT" "$text" >&2
    fi
}

blank_line() {
    if [ -n "$CURSOR_ROW" ]; then
        CURSOR_ROW=$((CURSOR_ROW + 1))
    else
        echo >&2
    fi
}

box_top() { emit_line "+$(rep $(( "$1" - 2 )) -)+"; }
box_bottom() { box_top "$1"; }  # same horizontal border shape as the top

# Pads both sides to fill the full width, not just left-centers — a
# real, hardware-reported bug otherwise: redraw_preview (text_entry's
# "prompt: buffer" line) calls this repeatedly on the same on-screen row
# as the buffer changes, with no full-frame redraw in between. Backspace
# (including the controller Back button, see the OTHER case in
# text_entry) shrinks the buffer, so the new centered text is shorter
# than what was already drawn — without right-padding, the deleted
# character's old glyph was simply never overwritten, silently sitting
# there even though the buffer itself was correctly shortened (visible
# once DONE was chosen and the real, shorter text came back). Every
# other call site here draws once per fresh screen (monitor_frame
# already cleared everything first), so the extra trailing spaces are
# invisible there — this only ever mattered for redraw_preview.
box_center_text() {
    local width="$1" text="$2" pad rem
    pad=$(( (width - ${#text}) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    rem=$(( width - pad - ${#text} ))
    [ "$rem" -lt 0 ] && rem=0
    emit_line "$(sp "$pad")${text}$(sp "$rem")"
}

# highlight=1 shows the row on a solid colored background (current
# theme's color+tier) with black text, instead of the ">...<" bracket
# markers this script used before 2026-07-28 — see the theme block's
# own note on why. Same indent as a normal row either way (no extra
# step-in), so only the background changes when a row becomes
# selected. Used for whichever item/cell is currently selected in
# select_menu and text_entry.
box_line() {
    local width="$1" text="$2" highlight="${3:-0}" inner row
    inner=$((width - 2))
    row="  $text"
    printf -v row '%-*s' "$inner" "$row"
    row="${row:0:$inner}"
    if [ "$highlight" = "1" ]; then
        row="${ESC}[$(current_theme_bg)m${ESC}[30m${row}${ESC}[0m${ESC}[40m${ESC}[$(current_theme_fg)m"
    fi
    emit_line "|${row}|"
}

# Same border shape as box_top, but written into the caller-named
# variable instead of printed directly — needed when this line itself
# has to become part of *another* line rather than a line of its own
# (see confirm_menu's outer double border, which embeds an inner box's
# border/content lines inside the outer border's own "| ... |" on the
# same physical row, so the outer border's side rails stay continuous
# instead of only appearing on the blank rows between inner boxes).
box_border_str() {
    local -n _box_border_str_out="$1"
    local width="$2"
    _box_border_str_out="+$(rep $(( width - 2 )) -)+"
}

# Same content-line shape as box_line, but written into the caller-named
# variable instead of printed directly. See box_border_str above and
# box_line's own note on the colored-background highlight.
box_content_str() {
    local -n _box_content_str_out="$1"
    local width="$2" text="$3" highlight="${4:-0}" inner row
    inner=$((width - 2))
    row="  $text"
    printf -v row '%-*s' "$inner" "$row"
    row="${row:0:$inner}"
    if [ "$highlight" = "1" ]; then
        row="${ESC}[$(current_theme_bg)m${ESC}[30m${row}${ESC}[0m${ESC}[40m${ESC}[$(current_theme_fg)m"
    fi
    _box_content_str_out="|${row}|"
}

# Clears the whole screen, then draws a plain rectangular frame around a
# screen cutout of CW columns x CH rows, with a 1-row/col blank margin
# between the border and the content. Every caller needs both (nothing
# calls this over a screen it wants to keep), so the clear lives here
# instead of being repeated at each call site. Centered on the actual
# terminal, by drawing every row at an absolute position rather than
# relying on the cursor already being at the top-left. Sets CURSOR_ROW/
# CURSOR_COL (and FRAME_ROW, for frame_done) so the caller's own
# box_top/box_line/etc. calls land inside the frame instead of needing to
# know its geometry themselves.
#
# `stty size < /dev/tty` was tried first to detect the real terminal
# size and confirmed on hardware to always fail — but that's specifically
# the `/dev/tty` device path failing to open, not this process lacking a
# terminal at all: plain `stty size` (querying whatever's already on this
# script's own stdin, the same fd read_key already reads from) works
# fine and reports the real, current resolution. This means centering
# genuinely adapts if the video mode/resolution changes, rather than
# assuming a fixed size. The literal fallback values below only matter
# if stdin somehow isn't a tty at all (e.g. testing in a sandbox with
# piped input).
monitor_frame() {
    local CW="$1" CH="$2"
    local margin=1
    local inner_w=$((CW + 2*margin))
    local inner_h=$((CH + 2*margin))
    local total_w=$((inner_w + 2))
    local total_h=$((inner_h + 2))
    local term_rows=67 term_cols=240 size start_row start_col
    local i border blank_row

    printf '\033[H\033[2J' >&2

    if size=$(stty size 2>/dev/null); then
        term_rows=${size% *}
        term_cols=${size#* }
    fi

    start_row=$(( (term_rows - total_h) / 2 + 1 ))
    start_col=$(( (term_cols - total_w) / 2 + 1 ))
    [ "$start_row" -lt 1 ] && start_row=1
    [ "$start_col" -lt 1 ] && start_col=1
    FRAME_ROW="$start_row"

    # Every blank interior row is identical, so build it once (2 forks
    # total) instead of once per row — this redraws on every keypress, and
    # inner_h can be 20+ for a menu with many profiles.
    border="+$(rep "$inner_w" -)+"
    blank_row="|$(sp "$inner_w")|"

    printf '\033[%d;%dH%s' "$start_row" "$start_col" "$border" >&2
    for ((i = 0; i < inner_h; i++)); do
        printf '\033[%d;%dH%s' $(( start_row + 1 + i )) "$start_col" "$blank_row" >&2
    done
    printf '\033[%d;%dH%s' $(( start_row + 1 + inner_h )) "$start_col" "$border" >&2

    CURSOR_ROW=$(( start_row + margin + 1 ))
    CURSOR_COL=$(( start_col + margin + 1 ))
}

# emit_line's cursor-positioned printf never ends with \n (it has to move
# the cursor to a specific row/col each time, not just append), so after
# the last line of a monitor_frame screen, the real terminal cursor is
# left sitting mid-row — right after that last line's text, still inside
# the frame. Anything printed next (plain `echo` messages, pause()'s
# prompt) would carry on from that same spot and run past the border
# instead of starting a clean line below it. Call this with the same
# content height passed to monitor_frame before returning control, to
# park the cursor just below the frame and clear anything stale beneath.
# Also clears CURSOR_ROW/CURSOR_COL back to "" — every caller did this
# itself right afterward anyway (there's no more "inside the frame" to
# position against once a screen is done), so it's folded in here rather
# than repeated at each call site.
frame_done() {
    local content_height="$1"
    local clear_row
    # monitor_frame(CW, content_height) draws content_height+4 rows total
    # starting at FRAME_ROW (1 top border + content_height+2 interior
    # rows, the +2 being monitor_frame's own 1-row margin on each side +
    # 1 bottom border) — so FRAME_ROW+content_height+4 is the first clean
    # row below it. Clears from there to the end of the screen.
    clear_row=$(( FRAME_ROW + content_height + 4 ))
    printf '\033[%d;1H\033[J' "$clear_row" >&2

    CURSOR_ROW=""
    CURSOR_COL=""
}

# ---------- splash screen ----------
# Shown once at startup, right before the main menu loop first runs —
# purely cosmetic, the only decorative art left in the script (an
# earlier version also had art flanking every menu box; removed so the
# splash is the one place with artwork). "Do the best you can, never
# error out": if the real terminal is smaller than this art, rows/
# columns that don't fit simply aren't positioned on screen rather than
# wrapping or failing the printf calls.
SPLASH_ART_WIDTH=58
SPLASH_ART=(
    " __  __ _ ____ _____           _____ ____   ____    _     "
    "|  \/  (_) ___|_   _|__ _ __  |  ___|  _ \ / ___|  / \    "
    "| |\/| | \___ \ | |/ _ \ '__| | |_  | |_) | |  _  / _ \   "
    "| |  | | |___) || |  __/ |    |  _| |  __/| |_| |/ ___ \  "
    "|_|  |_|_|____/ |_|\___|_|_   |_|   |_| __ \____/_/   \_\ "
    "| | | |___  ___ _ __  |  _ \ _ __ ___  / _(_) | ___  ___  "
    "| | | / __|/ _ \ '__| | |_) | '__/ _ \| |_| | |/ _ \/ __| "
    "| |_| \__ \  __/ |    |  __/| | | (_) |  _| | |  __/\__ \ "
    " \___/|___/\___|_|    |_|   |_|  \___/|_| |_|_|\___||___/ "
    "                                                          "
)
SPLASH_ART_HEIGHT=${#SPLASH_ART[@]}

show_splash() {
    local term_rows=67 term_cols=240 size start_row start_col i r

    printf '\033[H\033[2J' >&2

    if size=$(stty size 2>/dev/null); then
        term_rows=${size% *}
        term_cols=${size#* }
    fi

    # A single bordered box (matching the "+---+"/"|...|" look every
    # other screen in this script uses) around the whole of SPLASH_ART —
    # simplified from an earlier title-box-plus-separate-logo layout
    # once the artwork itself was pared down to just the title banner.
    local content_w box_w box_h border blank_row
    content_w=$(( SPLASH_ART_WIDTH + 2 ))
    box_w=$(( content_w + 2 ))
    border="+$(rep "$content_w" -)+"
    blank_row="|$(sp "$content_w")|"
    # +1 for a blank row of padding above the border itself, requested
    # separately from the box's own internal blank rows.
    box_h=$(( 1 + 1 + 1 + SPLASH_ART_HEIGHT + 1 + 1 ))

    start_row=$(( (term_rows - box_h) / 2 + 1 ))
    start_col=$(( (term_cols - box_w) / 2 + 1 ))
    [ "$start_row" -lt 1 ] && start_row=1
    [ "$start_col" -lt 1 ] && start_col=1

    r=$((start_row + 1))
    printf '\033[%d;%dH%s' "$r" "$start_col" "$border" >&2
    r=$((r + 1))

    if [ "$r" -le "$term_rows" ]; then
        printf '\033[%d;%dH%s' "$r" "$start_col" "$blank_row" >&2
        r=$((r + 1))
    fi

    for ((i = 0; i < SPLASH_ART_HEIGHT; i++)); do
        if [ "$r" -gt "$term_rows" ]; then
            break
        fi
        printf '\033[%d;%dH| %s |' "$r" "$start_col" "${SPLASH_ART[$i]}" >&2
        r=$((r + 1))
    done

    if [ "$r" -le "$term_rows" ]; then
        printf '\033[%d;%dH%s' "$r" "$start_col" "$blank_row" >&2
        r=$((r + 1))
    fi

    if [ "$r" -le "$term_rows" ]; then
        printf '\033[%d;%dH%s' "$r" "$start_col" "$border" >&2
        r=$((r + 1))
    fi

    # Auto-continues after 3 seconds; a keypress before then skips the
    # wait immediately instead of forcing it out.
    read -n 1 -s -r -t 3 || true
}

# ---------- input ----------

# Reads one keypress and reports UP/DOWN/LEFT/RIGHT/ENTER/BACKSPACE, or
# CHAR:<c> for any other printable key (used by text_entry's on-screen
# keyboard so a real keyboard can still type directly into it). Arrow keys
# arrive as an escape sequence (ESC [ A/B/C/D); a lone ESC times out
# waiting for the rest of the sequence and is treated as OTHER — a
# controller's Back button sends exactly this. OTHER means Backspace in
# text_entry, "go back" (select the list's last item) in select_menu
# (unless that caller opts out via NO_BACK_SHORTCUT=1) and menu_color_menu,
# and "No" in confirm_menu — see each function's own OTHER case for why.
# A closed/exhausted stdin also reads as an empty $key (same as Enter), but
# `read` itself fails in that case — checked here and reported as EOF so
# callers can exit instead of looping forever treating EOF as Enter.
read_key() {
    local key rest
    if ! read -n 1 -s -r key; then
        echo "EOF"
        return
    fi
    if [ "$key" = $'\x1b' ]; then
        read -n 2 -s -r -t 0.1 rest
        case "$rest" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            '[C') echo "RIGHT" ;;
            '[D') echo "LEFT" ;;
            *) echo "OTHER" ;;
        esac
    elif [ -z "$key" ]; then
        echo "ENTER"
    elif [ "$key" = $'\x7f' ] || [ "$key" = $'\b' ]; then
        echo "BACKSPACE"
    else
        echo "CHAR:$key"
    fi
}

# ---------- menus ----------

# Draws a highlightable menu and waits for Up/Down/Enter. All drawing goes
# to stderr so the chosen index (echoed at the end) is the only thing the
# caller's command substitution captures on stdout. $1 is the heading shown
# under the title bar; the remaining args are the menu items.
select_menu() {
    local heading="$1"
    shift
    local items=("$@")
    local count=${#items[@]}
    local selected=0
    local i item key width height items_row old
    local title="MiSTer User Profiles"
    local status1 status2 hint="Up/Down: Move    Enter: Select"

    # None of this changes across keypresses within one call, so it's
    # computed once here rather than on every redraw.
    status1="Active User: $(current_profile)"
    status2="Active RA User: $(current_ra_username)"
    width=$(box_width_for "$title" "$heading" "$status1" "$status2" "$hint" "${items[@]}")
    [ "$width" -lt 40 ] && width=40

    # Title+status box (5) + blank + heading + blank + item box
    # (2 + count) + blank + hint. Keep in sync with the draw sequence
    # below (and with monitor_frame's own frame_h math). An empty
    # heading (main menu — the title box already says "MiSTer User
    # Profiles", no need to repeat it) drops the heading line and one of
    # its flanking blanks, so 2 fewer rows.
    if [ -n "$heading" ]; then
        height=$(( 12 + count ))
    else
        height=$(( 10 + count ))
    fi

    # Everything except the item list is static for the life of this call
    # (nothing else changes it), so it's drawn exactly once here. Only the
    # two affected item rows get touched on each Up/Down — no full clear,
    # no re-drawing the frame/title/status/hint every keypress.
    monitor_frame "$width" "$height"

    box_top "$width"
    box_line "$width" "$title" 0
    box_line "$width" "$status1" 0
    box_line "$width" "$status2" 0
    box_bottom "$width"
    blank_line
    if [ -n "$heading" ]; then
        box_center_text "$width" "$heading"
        blank_line
    fi

    box_top "$width"
    items_row="$CURSOR_ROW"
    i=0
    for item in "${items[@]}"; do
        box_line "$width" "$item" "$([ "$i" -eq "$selected" ] && echo 1 || echo 0)"
        i=$((i + 1))
    done
    box_bottom "$width"
    blank_line
    box_center_text "$width" "$hint"

    while true; do
        key=$(read_key)
        case "$key" in
            UP|DOWN)
                old=$selected
                if [ "$key" = UP ]; then
                    selected=$(( (selected - 1 + count) % count ))
                else
                    selected=$(( (selected + 1) % count ))
                fi
                CURSOR_ROW=$(( items_row + old ))
                box_line "$width" "${items[$old]}" 0
                CURSOR_ROW=$(( items_row + selected ))
                box_line "$width" "${items[$selected]}" 1
                ;;
            EOF) exit 1 ;;
            ENTER)
                frame_done "$height"
                echo "$selected"
                return 0
                ;;
            OTHER)
                # A lone ESC — e.g. a controller's Back button — acts as
                # picking this list's last item, since that's always
                # "Back"/"Cancel" at every call site except the main menu,
                # which opts out via NO_BACK_SHORTCUT=1 (its last item is
                # "Quit" rather than a safe back action).
                if [ "${NO_BACK_SHORTCUT:-0}" != "1" ]; then
                    frame_done "$height"
                    echo "$((count - 1))"
                    return 0
                fi
                ;;
        esac
    done
}

# If MSG_BUFFER (see msg) has anything queued, draws it as one bordered
# inner box — each line word-wrapped to fit via wrap_text first, the same
# way confirm_menu already wraps its own prompt, so a msg() call doesn't
# need to be pre-split by hand to stay inside the box (some call sites
# used to split long messages across multiple msg calls themselves, e.g.
# relink's 4-line explanation, precisely because this function didn't
# wrap on its own — that assumption didn't hold everywhere: several
# single-msg-call lines, e.g. switch_profile's save/savestate path lines
# and delete_user's "Deleted '$name' (...)"  line, were long enough to
# silently truncate mid-word instead. box_content_str's own truncation
# still applies as a last resort, for a single word too long to fit even
# alone on its own wrapped line) — followed by a blank spacer row, then
# clears the buffer. Does nothing if empty. Draws only the *inner* box,
# never an outer border: shared by show_messages/pause and confirm_menu,
# which each wrap their own outer frame around whatever this adds plus
# their own content. Relies on `width`, `inner_line`, and `blank_inner`
# already being set in the caller's scope (dynamic scoping, same trick
# split_row/cell_label use elsewhere in this file) rather than taking
# them as parameters, since every call site already has them.
draw_pending_messages() {
    [ "${#MSG_BUFFER[@]}" -eq 0 ] && return
    local text line wrapped
    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"
    for text in "${MSG_BUFFER[@]}"; do
        # An explicitly empty msg() call (e.g. switch_profile's blank
        # separator row) is a deliberate blank line, not something to
        # wrap — wrap_text itself echoes nothing at all for empty input,
        # which would otherwise silently drop the row instead of leaving
        # it blank.
        if [ -z "$text" ]; then
            box_content_str inner_line "$width" "" 0
            emit_line "| ${inner_line} |"
            continue
        fi
        mapfile -t wrapped < <(wrap_text $((width - 4)) "$text")
        for line in "${wrapped[@]}"; do
            box_content_str inner_line "$width" "$line" 0
            emit_line "| ${inner_line} |"
        done
    done
    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"
    emit_line "| ${blank_inner} |"
    MSG_BUFFER=()
}

# Flushes whatever's queued in MSG_BUFFER (see msg) inside the standard
# outer double border, the same nested shape confirm_menu uses. With
# $1="wait", also shows a "Press any key to continue..." box inside that
# same frame afterward and waits for a keypress — this is pause() below.
# With no argument, just shows whatever's queued (if anything) and
# returns immediately without waiting — for the one spot in this script
# that has a pending message but doesn't come back here at all afterward
# (Quit's "rebooting" message, right before an actual reboot), so it
# still gets shown instead of silently dropped, without also making the
# reboot wait on a keypress that was never part of that flow.
show_messages() {
    local wait="${1:-}"
    local width=40
    local outer_w=$(( width + 4 ))
    local inner_line blank_inner
    printf -v blank_inner '%*s' "$width" ''
    local PAD_LEFT
    PAD_LEFT=$(msg_margin)

    if [ "${#MSG_BUFFER[@]}" -eq 0 ] && [ "$wait" != "wait" ]; then
        return
    fi

    blank_line
    box_top "$outer_w"
    emit_line "| ${blank_inner} |"

    draw_pending_messages

    if [ "$wait" = "wait" ]; then
        box_border_str inner_line "$width"
        emit_line "| ${inner_line} |"
        box_content_str inner_line "$width" "Press any key to continue..." 0
        emit_line "| ${inner_line} |"
        box_border_str inner_line "$width"
        emit_line "| ${inner_line} |"
        emit_line "| ${blank_inner} |"
    fi

    box_bottom "$outer_w"

    if [ "$wait" = "wait" ]; then
        read -n 1 -s -r
    fi
}

pause() { show_messages wait; }

# Highlightable Yes/No prompt. Prints the (word-wrapped) message and the
# Yes/No box once, both nested inside an outer double border — the same
# "outer frame around inner boxes" shape monitor_frame gives every other
# screen — then redraws just the two option lines in place on Up/Down
# (not a full-screen clear) so context printed above — e.g. the username
# being confirmed — stays visible. Returns 0 for Yes, 1 for No.
confirm_menu() {
    local prompt="$1"
    local options=("Yes" "No")
    local selected=1
    local i opt key width box_lines line wrapped
    # Doesn't use monitor_frame (by design — it prints inline so context
    # printed above, e.g. the username being confirmed, stays visible
    # instead of being cleared), so it builds its own outer border with
    # plain sequential prints instead of monitor_frame's absolute
    # positioning. Every row (blank or not) is composed as ONE string —
    # "| " + inner content, padded to fill, + " |" — and printed in a
    # single emit_line call, rather than printing the outer "|" and the
    # inner box's own line as separate prints. That composition is what
    # keeps the outer border's side rails continuous down every row
    # (matching monitor_frame's own look): drawing them as separate
    # lines left the outer "|" only on the blank rows between inner
    # boxes and missing everywhere the inner content itself printed — a
    # real, hardware-reported gap in an earlier version of this pass.
    local PAD_LEFT
    PAD_LEFT=$(msg_margin)

    # Fixed width (matches select_menu's own minimum, so this box isn't
    # visibly wider than the menu boxes around it), independent of both
    # the prompt's length and the options — a long prompt wraps to fit
    # instead of widening the box past the real terminal's width (a
    # real, hardware-confirmed bug when this was prompt-driven: the
    # box's border line itself wrapped, which threw off the "move cursor
    # up box_lines" redraw and made the box print a fresh copy below the
    # last one on every keypress instead of overwriting it in place —
    # see CLAUDE.md's "confirm_menu's box duplicating" note). outer_w is
    # this same inner width plus monitor_frame's own margin+border
    # formula (CW + 2*margin + 2 border chars), for the outer frame.
    width=40
    box_lines=$(( ${#options[@]} + 2 ))
    local outer_w=$(( width + 4 ))
    # box_lines (the inner Yes/No box's own top/2-options/bottom) plus
    # the outer border's closing blank row + bottom border below it — 2
    # more lines. The outer close is drawn up front, right after the
    # first options draw, so the frame looks fully enclosed immediately
    # (matching every other screen) instead of only after Enter is
    # pressed — a real, hardware-reported gap in an earlier version of
    # this polish pass. Because of that, every Up/Down redraw has to move
    # up over all of redraw_lines, not just box_lines, and reprint all of
    # it (the outer close included) to land the cursor back in the same
    # place afterward, ready for the next redraw.
    local redraw_lines=$(( box_lines + 2 ))

    mapfile -t wrapped < <(wrap_text $((width - 4)) "$prompt")

    local inner_line blank_inner
    printf -v blank_inner '%*s' "$width" ''

    box_top "$outer_w"
    emit_line "| ${blank_inner} |"

    # Anything still queued in MSG_BUFFER from before this call (e.g.
    # create_profile's status messages, still pending when the very next
    # thing to run is a confirm_menu rather than a pause) shows here,
    # inside this same outer frame, above this prompt's own message box —
    # see draw_pending_messages.
    draw_pending_messages

    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"
    for line in "${wrapped[@]}"; do
        box_content_str inner_line "$width" "$line" 0
        emit_line "| ${inner_line} |"
    done
    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"

    emit_line "| ${blank_inner} |"

    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"
    i=0
    for opt in "${options[@]}"; do
        box_content_str inner_line "$width" "$opt" "$([ "$i" -eq "$selected" ] && echo 1 || echo 0)"
        emit_line "| ${inner_line} |"
        i=$((i + 1))
    done
    box_border_str inner_line "$width"
    emit_line "| ${inner_line} |"

    emit_line "| ${blank_inner} |"
    box_bottom "$outer_w"

    while true; do
        key=$(read_key)
        case "$key" in
            UP|DOWN)
                selected=$(( (selected + 1) % 2 ))
                printf '\033[%dA' "$redraw_lines" >&2
                box_border_str inner_line "$width"
                emit_line "| ${inner_line} |"
                i=0
                for opt in "${options[@]}"; do
                    box_content_str inner_line "$width" "$opt" "$([ "$i" -eq "$selected" ] && echo 1 || echo 0)"
                    emit_line "| ${inner_line} |"
                    i=$((i + 1))
                done
                box_border_str inner_line "$width"
                emit_line "| ${inner_line} |"
                emit_line "| ${blank_inner} |"
                box_bottom "$outer_w"
                ;;
            EOF) exit 1 ;;
            ENTER)
                [ "$selected" -eq 0 ]
                return $?
                ;;
            OTHER)
                # A lone ESC — e.g. a controller's Back button — declines
                # the same as picking "No" (options[1]), regardless of
                # which option is currently highlighted. No redraw needed:
                # unlike UP/DOWN this doesn't move the highlight, it just
                # answers as though No had been chosen.
                return 1
                ;;
        esac
    done
}

# ---------- text entry ----------

# Centers text within a fixed width (used for the on-screen keyboard's grid
# cells, redrawn ~50 times per keypress, so this avoids forking a subshell
# per call — writes into the caller's named variable instead of stdout).
# Truncates rather than going negative if text is already wider.
pad_center() {
    local -n _pad_center_out="$1"
    local text="$2" width="$3" total pad_l pad_r spaces
    total=${#text}
    if [ "$total" -ge "$width" ]; then
        _pad_center_out="${text:0:$width}"
        return
    fi
    pad_l=$(( (width - total) / 2 ))
    pad_r=$(( width - total - pad_l ))
    printf -v spaces '%*s' "$width" ''
    _pad_center_out="${spaces:0:$pad_l}${text}${spaces:0:$pad_r}"
}

# text_entry's on-screen-keyboard rows are stored as single strings with
# cells joined by this separator (a control character that can never be a
# real password character), so ragged row lengths and cells like "!" or
# "," don't collide with the delimiter. Note "$*" is what actually honors
# IFS as a join character — plain `echo a b c` always joins with a space
# regardless of IFS, so building rows must go through this helper.
OSK_SEP=$'\x1f'
mkrow() { local IFS="$OSK_SEP"; printf '%s' "$*"; }

# Splits row $1 of osk_rows into the caller's own `cells` array. Relies on
# bash's dynamic scoping (neither `cells` nor `osk_rows` is declared local
# here, so this reads/writes whichever ones are in scope up the call
# stack — text_entry's own locals) rather than returning a value, since
# it's called on every keypress and every redraw of every row.
split_row() { IFS="$OSK_SEP" read -ra cells <<< "${osk_rows[$1]}"; }

# The following three helpers all rely on dynamic scoping into text_entry's
# locals (shift_state, cur_row, cur_col, cell_w, row_count, osk_rows,
# grid_row, grid_col, preview_row, prompt, mask, buffer, width) — same
# trick as split_row above. They let text_entry redraw only what actually
# changed on a keypress instead of clearing and repainting the whole
# screen every time.

# The label actually shown for osk_rows row $1, cell $2 — lowercased if
# it's a letter and shift_state is on.
cell_label() {
    split_row "$1"
    local label="${cells[$2]}"
    if [ "$shift_state" = "1" ] && [[ "$label" =~ ^[A-Z]$ ]]; then
        label="${label,,}"
    fi
    echo "$label"
}

# Builds the display text for grid cell (r,c) into the caller-named
# output variable. The highlighted cell shows a colored background
# (current theme's color+tier) with black text, same as box_line,
# instead of ">...<" bracket margins — margins stay plain spaces
# either way, so the cell's total width (cell_w) is unchanged. Shared
# by draw_grid (every cell) and redraw_cell (one cell).
render_cell() {
    local -n _render_cell_out="$1"
    local r="$2" c="$3" hl="$4" disp inner content
    disp=$(cell_label "$r" "$c")
    inner=$((cell_w - 2))
    pad_center content "$disp" "$inner"
    if [ "$hl" = "1" ]; then
        _render_cell_out="${ESC}[$(current_theme_bg)m${ESC}[30m ${content} ${ESC}[0m${ESC}[40m${ESC}[$(current_theme_fg)m"
    else
        _render_cell_out=" ${content} "
    fi
}

# Redraws a single grid cell in place at its exact row/col — used when
# only the highlighted cell moved (Up/Down/Left/Right), so nothing else on
# screen needs to be touched.
redraw_cell() {
    local r="$1" c="$2" hl="$3" padded
    render_cell padded "$r" "$c" "$hl"
    printf '\033[%d;%dH%s' $(( grid_row + r )) $(( grid_col + c * (cell_w + 1) )) "$padded" >&2
}

# Draws every cell of every row — used for the initial draw and for SHIFT
# (which relabels every letter cell at once, so there's no smaller region
# to target).
draw_grid() {
    local r c cells padded line hl
    CURSOR_ROW="$grid_row"
    for ((r = 0; r < row_count; r++)); do
        split_row "$r"
        line=""
        for ((c = 0; c < ${#cells[@]}; c++)); do
            if [ "$r" -eq "$cur_row" ] && [ "$c" -eq "$cur_col" ]; then
                hl=1
            else
                hl=0
            fi
            render_cell padded "$r" "$c" "$hl"
            if [ "$c" -eq 0 ]; then
                line="$padded"
            else
                line="$line $padded"
            fi
        done
        emit_line "$line"
    done
}

# Redraws just the "prompt: text" preview line — used whenever the buffer
# changes (typing, backspace, clear) without the highlight moving.
redraw_preview() {
    local display_buf preview
    if [ "$mask" = "1" ]; then
        display_buf=$(rep "${#buffer}" '*')
    else
        display_buf="$buffer"
    fi
    preview="$prompt: $display_buf"
    CURSOR_ROW="$preview_row"
    box_center_text "$width" "${preview:0:$width}"
}

# On-screen keyboard for entering text without a physical keyboard: a
# character grid navigated with Up/Down/Left/Right + Enter, the same input
# this whole script already reads for menus (so it works with a controller
# under the same assumptions as everything else here). A real keyboard
# still works too — printable keypresses are appended directly, and
# Backspace/Delete map to the grid's own BKSP action — so this is a
# hybrid: fast typing for anyone with a keyboard, full navigation for
# anyone without one.
#
# $1 = prompt shown above the grid. $2 = 1 to mask the entered text with
# * as each character is added (for passwords), 0 to show it plainly.
# Echoes the finished text to stdout when DONE is chosen (return 0), or
# nothing with a non-zero return if CANCEL is chosen.
text_entry() {
    local prompt="$1" mask="${2:-0}"
    local buffer="" shift_state=0
    local cur_row=0 cur_col=0
    local osk_rows=(
        "$(mkrow 1 2 3 A B C D E F G H I)"
        "$(mkrow 4 5 6 J K L M N O P Q R)"
        "$(mkrow 7 8 9 S T U V W X Y Z -)"
        "$(mkrow '!' '@' '#' '$' '%' '^' '&' '*' '(' ')')"
        "$(mkrow '-' '_' '=' '+' '.' ',' '/' '?')"
        "$(mkrow 0 SPACE SHIFT BKSP CLEAR DONE CANCEL)"
    )
    local row_count=${#osk_rows[@]}
    local cell_w=6
    local width height grid_row grid_col preview_row cells
    width=$(( 12 * cell_w + 11 ))
    [ "${#prompt}" -gt "$width" ] && width=${#prompt}
    height=$(( row_count + 4 ))

    # Draw everything exactly once: the frame, the preview line, and the
    # full grid. Every subsequent keypress only touches whichever specific
    # cell(s) or line actually changed (see redraw_cell/draw_grid/
    # redraw_preview above) instead of clearing and repainting the screen.
    monitor_frame "$width" "$height"

    preview_row="$CURSOR_ROW"
    redraw_preview
    blank_line

    grid_row="$CURSOR_ROW"
    grid_col="$CURSOR_COL"
    draw_grid

    blank_line
    box_center_text "$width" "Arrows: Move    Enter: Select"

    local key sel old_row old_col
    while true; do
        key=$(read_key)
        case "$key" in
            EOF) exit 1 ;;
            UP|DOWN)
                old_row=$cur_row
                old_col=$cur_col
                if [ "$key" = UP ]; then
                    cur_row=$(( (cur_row - 1 + row_count) % row_count ))
                else
                    cur_row=$(( (cur_row + 1) % row_count ))
                fi
                split_row "$cur_row"
                [ "$cur_col" -ge "${#cells[@]}" ] && cur_col=$((${#cells[@]} - 1))
                redraw_cell "$old_row" "$old_col" 0
                redraw_cell "$cur_row" "$cur_col" 1
                ;;
            LEFT|RIGHT)
                old_col=$cur_col
                split_row "$cur_row"
                if [ "$key" = LEFT ]; then
                    cur_col=$(( (cur_col - 1 + ${#cells[@]}) % ${#cells[@]} ))
                else
                    cur_col=$(( (cur_col + 1) % ${#cells[@]} ))
                fi
                redraw_cell "$cur_row" "$old_col" 0
                redraw_cell "$cur_row" "$cur_col" 1
                ;;
            BACKSPACE|OTHER)
                # OTHER covers a lone ESC with no follow-up arrow bytes —
                # e.g. a controller's Back button, which has no physical
                # Backspace key to send. Treating it the same as a real
                # Backspace/Delete keypress here gives controller-only
                # users a quick way to delete a character without
                # navigating the grid to BKSP each time.
                buffer="${buffer%?}"
                redraw_preview
                ;;
            CHAR:*)
                buffer+="${key#CHAR:}"
                redraw_preview
                ;;
            ENTER)
                split_row "$cur_row"
                sel="${cells[$cur_col]}"
                case "$sel" in
                    SPACE) buffer+=" "; redraw_preview ;;
                    SHIFT) shift_state=$((1 - shift_state)); draw_grid ;;
                    BKSP) buffer="${buffer%?}"; redraw_preview ;;
                    CLEAR) buffer=""; redraw_preview ;;
                    DONE)
                        frame_done "$height"
                        echo "$buffer"
                        return 0
                        ;;
                    CANCEL)
                        frame_done "$height"
                        return 1
                        ;;
                    *)
                        if [ "$shift_state" = "1" ] && [[ "$sel" =~ ^[A-Z]$ ]]; then
                            buffer+="${sel,,}"
                        else
                            buffer+="$sel"
                        fi
                        redraw_preview
                        ;;
                esac
                ;;
        esac
    done
}

# ---------- profile state & operations ----------

# The display name for profile $1 (its stable ID/folder name) — reads
# the .name file inside its folder, falling back to the ID itself if
# that's missing (a profile from before the ID/name split, back when
# the folder name *was* the display name — still works fine as its own
# ID going forward, no migration needed).
profile_name() {
    local id="$1"
    local f="$PROFILES_DIR/$id/.name"
    if [ -f "$f" ]; then
        cat "$f"
    else
        echo "$id"
    fi
}

# Whether any existing profile already has display name $1 — kept
# unique purely so the user isn't shown two identically-labeled entries
# in a menu; nothing internal depends on it, since real identity is the
# folder ID, not the name.
profile_name_exists() {
    local name="$1" id
    for id in $(list_profiles); do
        [ "$(profile_name "$id")" = "$name" ] && return 0
    done
    return 1
}

# Allocates the next sequential profile ID (User001, User002, ...) and
# persists the counter so IDs are never reused, even after a profile is
# removed — reusing one could accidentally resurrect an old save/RA
# association. Also guards against colliding with a pre-existing folder
# (e.g. a profile from before this ID scheme, still folder-named after
# its own display name) by skipping ahead until a free one is found.
next_profile_id() {
    local n id
    if [ -f "$NEXT_ID_FILE" ]; then
        n=$(cat "$NEXT_ID_FILE")
    else
        n=1
    fi
    while :; do
        printf -v id 'User%03d' "$n"
        n=$((n + 1))
        [ -d "$PROFILES_DIR/$id" ] || break
    done
    echo "$n" > "$NEXT_ID_FILE"
    printf '%s' "$id"
}

# The active profile's stable ID (raw content of CURRENT_FILE), or empty
# if none is active — for path-building. Never use this for anything
# shown on screen; see current_profile below for the display name.
current_profile_id() {
    if [ -f "$CURRENT_FILE" ]; then
        cat "$CURRENT_FILE"
    fi
    # Explicit, not redundant: every caller uses this unprotected (e.g.
    # id=$(current_profile_id)), and under set -euo pipefail that aborts
    # the whole script if this function's own exit status is ever
    # nonzero — which it otherwise would be whenever the "if" above is
    # false (no active profile yet, a common state).
    return 0
}

# The active profile's display name, or "(none)" if none is active —
# purely for what's shown on screen. Never use this for path-building;
# see current_profile_id above for the raw ID.
current_profile() {
    local id
    id=$(current_profile_id)
    if [ -n "$id" ]; then
        profile_name "$id"
    else
        echo "(none)"
    fi
}

current_ra_username() {
    local u
    u=$(grep -m1 '^username=' "$RA_CFG" 2>/dev/null | cut -d'=' -f2-)
    if [ -n "$u" ]; then
        echo "$u"
    else
        echo "(none)"
    fi
}

# Whether $1 is the profile (by ID) whose saves/savestates/inputs/RA
# login are currently live (i.e. renaming, removing, or editing it needs
# to also touch the active symlinks/RA_CFG, not just its own folder).
is_active_profile() {
    [ -f "$CURRENT_FILE" ] && [ "$(cat "$CURRENT_FILE")" = "$1" ]
}

# Lists profile IDs (folder names under PROFILES_DIR), not display
# names — callers needing display names go through profile_name.
# Excludes dot-prefixed directories (".trash", and any future
# maintenance folder added the same way) rather than naming .trash
# specifically — every real profile folder is a plain "User###" name,
# so this stays correct without needing to be updated each time a new
# dot-dir is added.
list_profiles() {
    find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null | sort
}

# Lists trash entry folder names ("<id>-<epoch>", see delete_user) under
# TRASH_DIR — used by restore_user to build its picker. Alphabetical sort
# on "<id>-<epoch>" isn't strictly chronological across different ids,
# but is good enough for a stable, predictable menu order (same
# trade-off list_profiles already makes).
list_trash() {
    find "$TRASH_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Permanently deletes profiles sitting in TRASH_DIR (see delete_user)
# once they're older than TRASH_RETENTION_DAYS. Trash folder names end in
# "-<epoch-seconds>" — the moment they were removed, encoded directly in
# the name — rather than relying on the folder's own filesystem mtime: a
# plain `mv` rename doesn't reliably update mtime, but the encoded
# timestamp always reflects the real removal time, so age is just
# integer arithmetic against the current epoch. If TRASH_RETENTION_DAYS
# is currently 0, every existing trash entry is "at least 0 days old" and
# gets purged immediately too — consistent with 0 meaning "don't keep
# removed profiles around" (see delete_user), no special-casing needed.
prune_trash() {
    local now entry base ts age_days
    now=$(date +%s)
    for entry in "$TRASH_DIR"/*; do
        [ -d "$entry" ] || continue
        base=$(basename "$entry")
        ts="${base##*-}"
        [[ "$ts" =~ ^[0-9]+$ ]] || continue
        age_days=$(( (now - ts) / 86400 ))
        if [ "$age_days" -ge "$TRASH_RETENTION_DAYS" ]; then
            rm -rf "$entry"
        fi
    done
}

# Folds a real (non-symlink) saves/savestates/inputs dir into the profile
# and removes it — shared by all three migrations in create_profile,
# which need identical treatment. Relies on the caller's $name for the
# message (dynamic scoping, same trick as split_row/relink). Uses
# msg_handoff, not msg — see msg's own comment for why (this always runs
# inside create_profile's command substitution subshell).
migrate_dir_into_profile() {
    local link="$1" dest="$2" what="$3"
    if [ -d "$link" ] && [ ! -L "$link" ]; then
        msg_handoff "Migrating existing $what into profile '$name'..."
        cp -a "$link/." "$dest/" 2>/dev/null || true
        rm -rf "$link"
    fi
}

# Creates a new profile with display name $1. Allocates a fresh,
# never-reused ID (see next_profile_id above) as the actual folder name
# — renaming later only ever rewrites its .name file, never this folder,
# which is the whole point of the ID/name split (see the design note at
# the top of this file). Also absorbs whatever's still real (not yet
# managed by this script) at the live saves/savestates/inputs/RA paths
# into this profile — the same first-run migration this script has
# always done, just targeting the new ID's folder instead of a
# name-based one, and now run unconditionally on every creation (each
# migrate_dir_into_profile call already no-ops on its own if there's
# nothing to migrate, so the caller no longer needs to pre-check).
# Echoes the new ID to stdout on success — every other message here goes
# through msg (queued into MSG_BUFFER, not printed), so nothing else
# touches stdout to corrupt that capture.
create_profile() {
    local name="$1" id dir first_ever

    # Whether any profile exists yet — checked before this one is
    # created, and used to gate the retroachievements.cfg migration
    # below. Unlike SAVES_LINK/SAVESTATES_LINK/INPUTS_LINK (which become
    # real symlinks once profile-managed, so "not a symlink" correctly
    # means "never migrated"), RA_CFG is never a symlink — switch_profile
    # makes it live with a plain file copy. So "$RA_CFG is a real file"
    # is true after ANY profile has ever been active (it's just whoever
    # was active last), not only on a genuine first run — without this
    # guard, every new profile silently inherited the previous active
    # profile's RA credentials.
    if [ -z "$(list_profiles)" ]; then
        first_ever=1
    else
        first_ever=0
    fi

    id=$(next_profile_id)
    dir="$PROFILES_DIR/$id"

    mkdir -p "$dir/saves" "$dir/savestates" "$dir/inputs"
    migrate_dir_into_profile "$SAVES_LINK" "$dir/saves" "saves"
    migrate_dir_into_profile "$SAVESTATES_LINK" "$dir/savestates" "savestates"
    migrate_dir_into_profile "$INPUTS_LINK" "$dir/inputs" "input mappings"
    if [ "$first_ever" = "1" ] && [ -f "$RA_CFG" ]; then
        msg_handoff "Migrating existing retroachievements.cfg into profile '$name'..."
        cp -a "$RA_CFG" "$dir/retroachievements.cfg"
    fi

    echo "$name" > "$dir/.name"

    if [ -f "$dir/retroachievements.cfg" ]; then
        : # already populated by the migration above
    elif [ -f "$BASE/retroachievements.cfg.template" ]; then
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

    msg_handoff "Created profile '$name' at $dir"
    msg_handoff "Edit $dir/retroachievements.cfg with that person's own"
    msg_handoff "RetroAchievements username/password before switching to it."
    echo "$id"
}

# Copies $1 to $2 only if $1 exists — the same "retroachievements.cfg is
# always there, menu.png is optional" copy shape shows up identically in
# switch_profile (into RA_CFG/MENU_PNG) and copy_user (into another
# profile's folder), so it's named once here instead of repeated as a
# 3-line if-block at every call site.
copy_if_exists() {
    if [ -f "$1" ]; then
        cp -a "$1" "$2"
    fi
}

# Points $link at $target, refusing (and returning 1) if $link exists and
# isn't already a symlink this script manages — used for SAVES_LINK,
# SAVESTATES_LINK, and INPUTS_LINK, which all need identical treatment.
relink() {
    local target="$1" link="$2"
    if [ -L "$link" ] || [ ! -e "$link" ]; then
        rm -f "$link"
    else
        msg "Refusing to touch $link — it's a real directory, not a"
        msg "symlink managed by this script. Run 'Switch profile' once on"
        msg "a fresh profile first so it can migrate the data safely, or"
        msg "move $link aside by hand."
        return 1
    fi
    ln -s "$target" "$link"
}

switch_profile() {
    local id="$1"
    local dir="$PROFILES_DIR/$id"
    local name

    if [ ! -d "$dir" ]; then
        msg "No such profile: $id"
        return 1
    fi
    name=$(profile_name "$id")

    # Profiles created before input-mapping support existed won't have
    # this subfolder yet — create it on first touch instead of erroring.
    mkdir -p "$dir/inputs"
    mkdir -p "$(dirname "$INPUTS_LINK")"
    relink "$dir/saves" "$SAVES_LINK" || return 1
    relink "$dir/savestates" "$SAVESTATES_LINK" || return 1
    relink "$dir/inputs" "$INPUTS_LINK" || return 1

    copy_if_exists "$dir/retroachievements.cfg" "$RA_CFG"

    # Optional: a profile's "menu.png" (set via the "Set Wallpaper" menu,
    # see set_wallpaper below) gives that person their own OSD wallpaper.
    # Not every profile will have one, unlike RA_CFG which every profile
    # always has — copy_if_exists handles both the same way regardless.
    copy_if_exists "$dir/menu.png" "$MENU_PNG"

    echo "$id" > "$CURRENT_FILE"

    msg "Switched to profile '$name'."
    msg "Saves      -> $dir/saves"
    msg "Savestates -> $dir/savestates"
    msg "Inputs     -> $dir/inputs"
    msg "RA cfg     -> $dir/retroachievements.cfg"
    [ -f "$dir/menu.png" ] && msg "Wallpaper  -> $dir/menu.png"
    msg ""

    local ra_user
    ra_user=$(grep -m1 '^username=' "$RA_CFG" 2>/dev/null | cut -d'=' -f2-)
    msg "RetroAchievements username now active: ${ra_user:-<empty>}"
    if ! confirm_menu "Is that the correct username?"; then
        msg "Not marking this as switched — edit $dir/retroachievements.cfg"
        msg "with the correct username, then select '$name' again."
        return 1
    fi

    msg "A reboot will be offered when you choose Quit, so the RA-enabled"
    msg "MiSTer binary re-reads the new credentials cleanly."
}

# Rewrites just the username=/password= lines of a retroachievements.cfg,
# leaving every other setting and comment untouched. Uses awk (not sed)
# so passwords containing /, &, or \ can't break the substitution.
update_ra_credentials() {
    local cfg="$1" user="$2" pass="$3" tmp="$1.new"
    awk -v u="$user" -v p="$pass" '
        /^username=/ { print "username=" u; next }
        /^password=/ { print "password=" p; next }
        { print }
    ' "$cfg" > "$tmp"
    mv "$tmp" "$cfg"
}

# Returns 1 (no changes made) if either field is cancelled from the
# on-screen keyboard.
prompt_ra_login() {
    local dir="$1" ra_user ra_pass
    ra_user=$(text_entry "RA Username" 0) || return 1
    ra_pass=$(text_entry "RA Password" 1) || return 1
    update_ra_credentials "$dir/retroachievements.cfg" "$ra_user" "$ra_pass"
}

# ---------- manage users ----------

# Prompts for a new profile display name and validates it (non-empty,
# not already taken) — shared by rename_user, copy_user, and the main
# menu's "Create New User" flow, which all need exactly this check
# before doing their own (different) work with the result.
get_new_profile_name() {
    local prompt="$1" new
    new=$(text_entry "$prompt" 0) || return 1

    # The caller captures this function's whole output via $(...) — safe
    # regardless here since msg only queues into MSG_BUFFER (see msg),
    # touching no file descriptor at all, but the final `echo "$new"`
    # below still must be the only real stdout output.
    if [ -z "$new" ]; then
        msg "Name cannot be empty."
        pause
        return 1
    fi
    if profile_name_exists "$new"; then
        msg "A profile named '$new' already exists."
        pause
        return 1
    fi

    echo "$new"
}

# Renames profile $1 (its ID) by rewriting only its .name file — the
# folder itself, and every live symlink pointing at it, are completely
# untouched. This used to mv the whole profile folder to the new name
# and then relink saves/savestates/inputs to match; if the live paths
# weren't proper symlinks at that exact moment for any reason, the
# relink step silently skipped itself while the rename still reported
# success, leaving gameplay writing into a path the renamed profile no
# longer tracked — a real data-loss bug, not hypothetical. Not possible
# anymore: nothing about where the data lives ever changes, so there's
# nothing left to get out of sync.
rename_user() {
    local id="$1" old_name new_name

    old_name=$(profile_name "$id")
    new_name=$(get_new_profile_name "New name for '$old_name'") || return 1

    echo "$new_name" > "$PROFILES_DIR/$id/.name"

    msg "Renamed '$old_name' to '$new_name'."
    pause
    return 0
}

copy_user() {
    local src_id="$1" src_name new_name new_id dir_src dir_new

    src_name=$(profile_name "$src_id")
    new_name=$(get_new_profile_name "New name for the copy of '$src_name'") || return 1

    new_id=$(next_profile_id)
    dir_src="$PROFILES_DIR/$src_id"
    dir_new="$PROFILES_DIR/$new_id"

    mkdir -p "$dir_new" "$dir_src/inputs"
    cp -a "$dir_src/saves" "$dir_new/saves"
    cp -a "$dir_src/savestates" "$dir_new/savestates"
    cp -a "$dir_src/inputs" "$dir_new/inputs"
    copy_if_exists "$dir_src/retroachievements.cfg" "$dir_new/retroachievements.cfg"
    copy_if_exists "$dir_src/menu.png" "$dir_new/menu.png"
    echo "$new_name" > "$dir_new/.name"

    msg "Copied '$src_name' (saves, savestates, inputs, RA login) to '$new_name'."
    pause
    return 0
}

# Deletes profile $1 (its ID). Named "Delete User" on screen (was
# "Remove User" — too easy to misread against "Rename User" one line up
# in the same list, especially skimming quickly). Unless
# TRASH_RETENTION_DAYS is 0, this moves the folder into TRASH_DIR rather
# than deleting it outright — a `mv` on the same filesystem is an
# instant rename, not a copy, so this costs nothing extra in disk space
# or time over a real delete. Gives a real undo window (see
# restore_user) for what's otherwise the one truly irreversible action
# in this script (saves/savestates that exist nowhere else), unlike
# rename/copy/edit-login which never destroy anything. prune_trash (run
# once at startup) purges anything past TRASH_RETENTION_DAYS; the user
# controls that window via "Trash Settings" on the main menu, including
# setting it to 0 to skip the trash and delete immediately, same as
# before this existed.
delete_user() {
    local id="$1" name retention_note trash_dest

    name=$(profile_name "$id")
    if [ "$TRASH_RETENTION_DAYS" = "0" ]; then
        retention_note="deleted immediately — not recoverable"
    else
        # Kept short deliberately — this is the confirm_menu prompt text,
        # and a long one risks wrapping on the real console (see
        # confirm_menu's box-width note); "Restore User" is already a
        # visible main-menu item, doesn't need repeating here too.
        retention_note="kept in trash for $TRASH_RETENTION_DAYS day(s)"
    fi
    if ! confirm_menu "Delete '$name' and all their saves/savestates/inputs/RA login? ($retention_note)"; then
        return 1
    fi

    if is_active_profile "$id"; then
        # Bare "[ cond ] && action" aborts the whole script under
        # set -e whenever cond is false (see prune_trash's identical fix
        # and the "Soft-delete trash for Delete User" note in
        # CLAUDE.md) — real if-blocks here so a live path that somehow
        # isn't a proper symlink at this exact moment doesn't crash the
        # deletion mid-way through instead of just skipping that link.
        if [ -L "$SAVES_LINK" ]; then
            rm -f "$SAVES_LINK"
        fi
        if [ -L "$SAVESTATES_LINK" ]; then
            rm -f "$SAVESTATES_LINK"
        fi
        if [ -L "$INPUTS_LINK" ]; then
            rm -f "$INPUTS_LINK"
        fi
        rm -f "$CURRENT_FILE"
        msg "'$name' was the active profile — select another profile"
        msg "before playing anything."
    fi

    if [ "$TRASH_RETENTION_DAYS" = "0" ]; then
        rm -rf "$PROFILES_DIR/$id"
    else
        trash_dest="$TRASH_DIR/${id}-$(date +%s)"
        mv "$PROFILES_DIR/$id" "$trash_dest"
    fi
    msg "Deleted '$name' ($retention_note)."
    pause
    return 0
}

edit_ra_login() {
    local id="$1"
    local dir="$PROFILES_DIR/$id" name

    name=$(profile_name "$id")
    if ! prompt_ra_login "$dir"; then
        msg "Cancelled — RetroAchievements login for '$name' unchanged."
        pause
        return
    fi
    msg "Updated RetroAchievements login for '$name'."

    if is_active_profile "$id"; then
        cp -a "$dir/retroachievements.cfg" "$RA_CFG"
        switched=true
        msg "'$name' is the active profile — credentials refreshed."
        msg "A reboot will be offered when you choose Quit."
    fi

    pause
}

# Lets the user assign one of the .png files already sitting in
# WALLPAPERS_DIR as this profile's menu.png, instead of needing SFTP for
# every wallpaper change — SFTP is still how images get onto the SD card
# in the first place (this script can't fetch or create one), but once
# they're staged in that one folder, assigning/reassigning them to any
# profile happens entirely from this menu.
# Display names of every profile (other than $2, if given) whose
# menu.png is byte-identical to the file at $1. Wallpapers are a plain
# copy-in from a shared staging folder, so nothing stops two profiles
# from ending up with the same image — and since nothing dynamically
# stamps the profile name onto it (checked: no ImageMagick, ffmpeg, or
# Python PIL/Pillow on this MiSTer install to do that), a shared image
# gives no way to tell whose profile is actually active just by looking
# at the wallpaper. Used by set_wallpaper to flag that before it happens
# rather than leave it a silent surprise.
wallpaper_users() {
    local src="$1" exclude_id="${2:-}" id other
    for id in $(list_profiles); do
        [ "$id" = "$exclude_id" ] && continue
        other="$PROFILES_DIR/$id/menu.png"
        if [ -f "$other" ] && cmp -s "$src" "$other"; then
            profile_name "$id"
        fi
    done
}

set_wallpaper() {
    local id="$1"
    local dir="$PROFILES_DIR/$id" name
    local files names choice src

    name=$(profile_name "$id")
    mapfile -t files < <(find "$WALLPAPERS_DIR" -maxdepth 1 -type f -iname '*.png' -printf '%f\n' 2>/dev/null | sort)
    if [ "${#files[@]}" -eq 0 ]; then
        msg "No wallpapers found — drop .png files into"
        msg "$WALLPAPERS_DIR"
        msg "first, then try again."
        pause
        return
    fi

    names=("${files[@]}")
    names+=("Cancel")

    choice=$(select_menu "Set Wallpaper for $name" "${names[@]}")
    if [ "$choice" -eq "${#files[@]}" ]; then
        return
    fi

    src="$WALLPAPERS_DIR/${files[$choice]}"

    local sharers joined u
    mapfile -t sharers < <(wallpaper_users "$src" "$id")
    if [ "${#sharers[@]}" -gt 0 ]; then
        joined="${sharers[0]}"
        for u in "${sharers[@]:1}"; do
            joined="$joined, $u"
        done
        if ! confirm_menu "This image is already used by $joined. Assign it to $name anyway?"; then
            return
        fi
    fi

    cp -a "$src" "$dir/menu.png"
    msg "Set '${files[$choice]}' as $name's wallpaper."

    if is_active_profile "$id"; then
        cp -a "$src" "$MENU_PNG"
        switched=true
        msg "'$name' is the active profile — wallpaper refreshed."
        msg "A reboot will be offered when you choose Quit for it to show."
    fi

    pause
}

# Shared by every Manage Users action that operates on an existing profile
# (Copy/Rename/Edit RA Login/Set Wallpaper/Delete) — unlike the old
# per-profile "Manage <name>" submenu, the action is picked first now, so
# each of those needs its own "which user?" step afterward instead. Echoes
# the chosen id and returns 0, or returns 1 (nothing echoed) on Cancel or
# if there are no profiles yet.
pick_managed_user() {
    local heading="$1" ids items selected id

    mapfile -t ids < <(list_profiles)
    if [ "${#ids[@]}" -eq 0 ]; then
        msg "No profiles yet — use Create User first."
        pause
        return 1
    fi

    items=()
    for id in "${ids[@]}"; do
        items+=("$(profile_name "$id")")
    done
    items+=("Cancel")

    selected=$(select_menu "$heading" "${items[@]}")
    if [ "$selected" -eq "${#ids[@]}" ]; then
        return 1
    fi

    echo "${ids[$selected]}"
}

# Was inline in the main menu loop before the Select User/Manage Users/
# Settings reorganization — moved here since "Create User" is now one of
# several actions on the Manage Users menu rather than its own main-menu
# item.
manage_create_user() {
    local newname newid cur_before_id cur_before_name

    newname=$(get_new_profile_name "New profile name") || return
    newid=$(create_profile "$newname")
    collect_handoff_messages

    cur_before_id="$(current_profile_id)"
    if [ -n "$cur_before_id" ]; then
        cur_before_name="$(profile_name "$cur_before_id")"
        if confirm_menu "Copy $cur_before_name's controller mappings to this new profile?"; then
            mkdir -p "$PROFILES_DIR/$cur_before_id/inputs"
            cp -a "$PROFILES_DIR/$cur_before_id/inputs/." "$PROFILES_DIR/$newid/inputs/"
            msg "Copied controller mappings from '$cur_before_name'."
        fi
    fi

    if confirm_menu "Enter this user's RetroAchievements username and password now?"; then
        prompt_ra_login "$PROFILES_DIR/$newid" || true
    fi

    if switch_profile "$newid"; then
        switched=true
    fi
    pause
}

manage_copy_user() {
    local id
    id=$(pick_managed_user "Copy User") || return
    copy_user "$id"
}

manage_rename_user() {
    local id
    id=$(pick_managed_user "Rename User") || return
    rename_user "$id"
}

manage_edit_ra_login() {
    local id
    id=$(pick_managed_user "Edit RA Login") || return
    edit_ra_login "$id"
}

manage_set_wallpaper() {
    local id
    id=$(pick_managed_user "Set Wallpaper") || return
    set_wallpaper "$id"
}

manage_delete_user() {
    local id
    id=$(pick_managed_user "Delete User") || return
    delete_user "$id"
}

# Flat action list, not a profile picker — reorganized 2026-07-29 so
# Select User (switching) and Manage Users (everything else) are separate
# main-menu sections instead of one combined "Select <name> / Create New
# User / Manage Users / Restore User" list. Every action loops back here
# afterward (whether it succeeded, was cancelled, or found no profiles);
# only "Back" returns to Main Menu. Delete User sits right above Back,
# deliberately last — it's the one truly destructive/rarely-used action
# here, so it shouldn't sit above the everyday ones where a careless
# Down-press could land on it.
manage_users_menu() {
    local action_items=("Create User" "Copy User" "Rename User" "Edit RA Login" "Set Wallpaper" "Restore User" "Delete User" "Back")
    local selected

    while true; do
        selected=$(select_menu "Manage Users" "${action_items[@]}")
        # `|| true` on every action: each of these can legitimately return
        # nonzero somewhere inside (Cancel on the user picker, a declined
        # confirm_menu, an empty/duplicate name, etc.) — a normal, expected
        # outcome, not a script-level error. Called bare like this under
        # `set -e`, a nonzero return here would abort the whole script
        # instead of just looping back to this menu — a real bug, hit via
        # a plain "No" on Delete User's confirm, not just the new
        # controller-Back-as-No shortcut that happened to make it easy to
        # trigger. See CLAUDE.md's "set -e gotcha" notes for the general
        # pattern; this is the same class, just via a function's own
        # return code rather than a bare `[ cond ] && action`.
        case "$selected" in
            0) manage_create_user || true ;;
            1) manage_copy_user || true ;;
            2) manage_rename_user || true ;;
            3) manage_edit_ra_login || true ;;
            4) manage_set_wallpaper || true ;;
            5) restore_user || true ;;
            6) manage_delete_user || true ;;
            7) return ;;
        esac
    done
}

# The main menu's "Select User" item — was a flat list of "Select <name>"
# items directly on the main menu before the reorganization above; now its
# own section so the main menu stays a fixed 4 items regardless of profile
# count. Loops back to itself after a switch (so trying a couple of
# profiles in a row doesn't mean re-entering this menu each time); only
# "Back" returns to Main Menu.
select_user_menu() {
    local ids items selected target_id id

    while true; do
        mapfile -t ids < <(list_profiles)

        if [ "${#ids[@]}" -eq 0 ]; then
            msg "No profiles yet — use Manage Users to create one."
            pause
            return
        fi

        items=()
        for id in "${ids[@]}"; do
            items+=("$(profile_name "$id")")
        done
        items+=("Back")

        selected=$(select_menu "Select User" "${items[@]}")
        if [ "$selected" -eq "${#ids[@]}" ]; then
            return
        fi

        target_id="${ids[$selected]}"
        if switch_profile "$target_id"; then
            switched=true
        fi
        pause
    done
}

# Redraws menu_color_menu's whole screen from scratch: title/status box,
# heading, the mixed header+item box, hint. Used both for the initial
# draw and to repaint after applying a color/brightness change — unlike
# select_menu's Up/Down redraw (which only ever touches the two affected
# rows), theme_on's \033[2J clears the whole screen and the new color
# needs a full repaint regardless, so there's no incremental option here.
# Deliberately not self-contained: reads/writes its caller's own local
# variables (title/status1/status2/heading/hint/width/height/row_label/
# row_kind/selected/items_row) via bash's dynamic scoping instead of
# parameters — the same trick split_row/relink already rely on elsewhere
# in this file — since this only ever makes sense called from inside
# menu_color_menu.
draw_menu_color_screen() {
    monitor_frame "$width" "$height"
    box_top "$width"
    box_line "$width" "$title" 0
    box_line "$width" "$status1" 0
    box_line "$width" "$status2" 0
    box_bottom "$width"
    blank_line
    box_center_text "$width" "$heading"
    blank_line

    box_top "$width"
    items_row="$CURSOR_ROW"
    local r sel_idx=0
    for r in "${!row_label[@]}"; do
        if [ "${row_kind[$r]}" = "header" ]; then
            box_line "$width" "${row_label[$r]}" 0
        else
            box_line "$width" "${row_label[$r]}" "$([ "$sel_idx" -eq "$selected" ] && echo 1 || echo 0)"
            sel_idx=$((sel_idx + 1))
        fi
    done
    box_bottom "$width"
    blank_line
    box_center_text "$width" "$hint"
}

# Colors and Brightness on one combined screen — reorganized 2026-07-29,
# twice: first into a Colors/Brightness/Back chooser leading to two
# separate screens, then (this version) merged back into a single page
# with "Colors" and "Brightness" as plain section labels above their own
# lists, per explicit request ("I want colors and brightness to be in
# the same menu page just put a section description before the
# different lists"). Up/Down moves through the 7 colors, then Bright,
# then Dark, then Back as one combined list — the two section-label rows
# are drawn but never highlightable, skipped entirely by the Up/Down
# math (see sel_to_row below). Picking a color or a brightness applies
# it immediately and stays on this same screen (same "preview each one
# easily" behavior requested for the two-screen version, carried over
# here) — only "Back" exits, to Settings.
menu_color_menu() {
    local title="MiSTer User Profiles"
    local heading="Menu Color"
    local status1 status2 hint="Up/Down: Move    Enter: Select"
    local width height key selected old items_row tier_idx n_colors
    local row_label=() row_kind=() sel_to_row=() c r

    row_label=("Colors:")
    row_kind=("header")
    for c in "${THEME_NAMES[@]}"; do
        row_label+=("  $c")
        row_kind+=("item")
    done
    row_label+=("Brightness:")
    row_kind+=("header")
    row_label+=("  Bright" "  Dark" "Back")
    row_kind+=("item" "item" "item")

    for r in "${!row_kind[@]}"; do
        [ "${row_kind[$r]}" = "item" ] && sel_to_row+=("$r")
    done
    local sel_count=${#sel_to_row[@]}
    n_colors=${#THEME_NAMES[@]}
    selected=0

    status1="Active User: $(current_profile)"
    status2="Active RA User: $(current_ra_username)"
    width=$(box_width_for "$title" "$heading" "$status1" "$status2" "$hint" "${row_label[@]}")
    [ "$width" -lt 40 ] && width=40
    height=$(( 12 + ${#row_label[@]} ))

    draw_menu_color_screen

    while true; do
        key=$(read_key)
        case "$key" in
            UP|DOWN)
                old=$selected
                if [ "$key" = UP ]; then
                    selected=$(( (selected - 1 + sel_count) % sel_count ))
                else
                    selected=$(( (selected + 1) % sel_count ))
                fi
                CURSOR_ROW=$(( items_row + sel_to_row[old] ))
                box_line "$width" "${row_label[${sel_to_row[old]}]}" 0
                CURSOR_ROW=$(( items_row + sel_to_row[selected] ))
                box_line "$width" "${row_label[${sel_to_row[selected]}]}" 1
                ;;
            EOF) exit 1 ;;
            ENTER)
                if [ "$selected" -eq "$((sel_count - 1))" ]; then
                    frame_done "$height"
                    return
                fi
                if [ "$selected" -lt "$n_colors" ]; then
                    THEME_INDEX="$selected"
                    echo "${THEME_NAMES[$THEME_INDEX]}" > "$THEME_FILE"
                else
                    tier_idx=$(( selected - n_colors ))
                    if [ "$tier_idx" -eq 0 ]; then
                        THEME_TIER="bright"
                    else
                        THEME_TIER="dark"
                    fi
                    echo "$THEME_TIER" > "$THEME_TIER_FILE"
                fi
                theme_on
                draw_menu_color_screen
                ;;
            OTHER)
                # A lone ESC — e.g. a controller's Back button — acts as
                # picking "Back" (the last selectable row), same as every
                # select_menu-based screen's own OTHER handling.
                frame_done "$height"
                return
                ;;
        esac
    done
}

# Lets the user pick how long "Delete User" keeps a deleted profile in
# TRASH_DIR before prune_trash purges it for good (see TRASH_RETENTION_
# OPTIONS/DAYS above and delete_user). Persists the choice the same way
# menu_color_menu does, and prunes immediately after a change so picking
# a shorter window (or 0, for instant deletion) takes effect right away
# instead of waiting for the next launch. The heading shows the current
# setting (so opening this screen doesn't require already remembering
# it), and "Back" — the current setting's own index, tacked onto the end
# — leaves it unchanged, since every other item here applies immediately
# and there was previously no way to just look without changing anything.
change_trash_retention() {
    local labels=() opt choice current_label i=0 idx=0
    for opt in "${TRASH_RETENTION_OPTIONS[@]}"; do
        if [ "$opt" = "0" ]; then
            labels+=("Instant (no trash)")
        elif [ "$opt" = "1" ]; then
            labels+=("1 day")
        else
            labels+=("$opt days")
        fi
        [ "$opt" = "$TRASH_RETENTION_DAYS" ] && idx=$i
        i=$((i + 1))
    done
    current_label="${labels[$idx]}"
    labels+=("Back")

    choice=$(select_menu "Current: $current_label" "${labels[@]}")
    if [ "$choice" -eq "${#TRASH_RETENTION_OPTIONS[@]}" ]; then
        return
    fi
    TRASH_RETENTION_DAYS="${TRASH_RETENTION_OPTIONS[$choice]}"
    echo "$TRASH_RETENTION_DAYS" > "$TRASH_RETENTION_FILE"
    prune_trash
}

# The main menu's "Settings" item, grouping Menu Color and Trash Settings
# under one section instead of two separate main-menu items. Loops until
# "Back" is chosen, same reasoning as manage_users_menu/select_user_menu —
# both menu_color_menu and change_trash_retention already return to
# whatever called them when done, so no change was needed inside either.
settings_menu() {
    local selected
    while true; do
        selected=$(select_menu "Settings" "Menu Color" "Trash Settings" "Back")
        # `|| true` for the same reason as manage_users_menu's own case
        # statement — both targets happen to always return 0 today, but
        # nothing should ever let a nonzero return from here abort the
        # whole script instead of just looping back to Settings.
        case "$selected" in
            0) menu_color_menu || true ;;
            1) change_trash_retention || true ;;
            2) return ;;
        esac
    done
}

# Lets the user pick a profile out of TRASH_DIR (see delete_user) and
# move it back into PROFILES_DIR under its original ID — the exact
# reverse of delete_user's mv, so just as cheap (a same-filesystem
# rename, not a copy). Each entry is labeled with its saved display name
# plus how long ago it was deleted, both read directly out of the trash
# folder itself (not through profile_name/list_profiles, which only look
# inside PROFILES_DIR). Refuses if a profile with that ID already exists
# in PROFILES_DIR — shouldn't normally happen, since IDs are never
# reused, but next_profile_id only checks PROFILES_DIR, not TRASH_DIR, so
# a corrupted/hand-edited .next_id could in theory produce a collision;
# better to refuse and ask for manual cleanup than silently clobber an
# active profile.
restore_user() {
    local entries items choice entry id ts trash_name now age_days label

    mapfile -t entries < <(list_trash)
    if [ "${#entries[@]}" -eq 0 ]; then
        msg "Trash is empty — nothing to restore."
        pause
        return
    fi

    now=$(date +%s)
    items=()
    for entry in "${entries[@]}"; do
        id="${entry%-*}"
        ts="${entry##*-}"
        if [ -f "$TRASH_DIR/$entry/.name" ]; then
            trash_name=$(cat "$TRASH_DIR/$entry/.name")
        else
            trash_name="$id"
        fi
        age_days=$(( (now - ts) / 86400 ))
        if [ "$age_days" -le 0 ]; then
            label="$trash_name (deleted today)"
        elif [ "$age_days" -eq 1 ]; then
            label="$trash_name (deleted 1 day ago)"
        else
            label="$trash_name (deleted $age_days days ago)"
        fi
        items+=("$label")
    done
    items+=("Cancel")

    choice=$(select_menu "Restore User" "${items[@]}")
    if [ "$choice" -eq "${#entries[@]}" ]; then
        return
    fi

    entry="${entries[$choice]}"
    id="${entry%-*}"

    if [ -e "$PROFILES_DIR/$id" ]; then
        msg "Can't restore — a profile with ID '$id' already exists in"
        msg "$PROFILES_DIR. This shouldn't normally happen; check by hand."
        pause
        return
    fi

    mv "$TRASH_DIR/$entry" "$PROFILES_DIR/$id"
    msg "Restored '$(profile_name "$id")'."
    pause
}

# ---------- main menu loop ----------

# True once any action this session actually changed the
# saves/savestates/inputs links or RA_CFG (switching, creating+switching,
# or editing the active profile's login) — Quit only offers a reboot when
# this is true, since a reboot doesn't fix anything otherwise.
switched=false

# Once per launch is enough — this isn't a long-running process, so
# there's no ongoing session to prune mid-way through.
prune_trash
show_splash

# Fixed 4-item list, unlike the old flat menu (profile list + 5 actions,
# whose size and index math depended on how many profiles existed).
# Reorganized 2026-07-29: "Select <name>" items and "Create New User"/
# "Restore User" moved into select_user_menu/manage_users_menu, and "Menu
# Color"/"Trash Settings" moved into settings_menu — see those functions.
while true; do
    # NO_BACK_SHORTCUT: this is the top of the menu tree — there's
    # nowhere to "go back" to, and its last item is "Quit" rather than a
    # safe back action, so the controller Back button is a no-op here
    # (see select_menu's OTHER case) instead of quitting the script.
    selected=$(NO_BACK_SHORTCUT=1 select_menu "" "Select User" "Manage Users" "Settings" "Quit")
    # `|| true` for the same reason as manage_users_menu's/settings_menu's
    # own case statements — a nonzero return from any of these should
    # never abort the whole script instead of just looping back here.
    case "$selected" in
        0) select_user_menu || true ;;
        1) manage_users_menu || true ;;
        2) settings_menu || true ;;
        3)
            if [ "$switched" = true ]; then
                msg "A profile was switched — rebooting so it takes effect."
                show_messages
                reboot
            fi
            exit 0
            ;;
    esac
done
