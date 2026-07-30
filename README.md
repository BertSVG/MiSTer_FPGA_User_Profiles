# mister_profiles.sh

Per-user profiles for MiSTer FPGA — lets multiple people who share one
MiSTer each have their own RetroAchievements login, their own save
games / save states, and their own controller input mappings, switchable
from a controller-friendly on-screen menu.

## A note on how this was built

The method of creating user profiles was created and tested by BertSVG,
but everything in that process was tediously done manually
one step at a time. This script automates that exact same process into
a streamlined menu for ease of use. This script was developed with
AI assistance (Claude), but every change was tested end-to-end on
real MiSTer hardware by BertSVG before being kept — not just checked
for syntax. If something as important as your save files is on the line,
that's fair to want proof of, not just a promise, so here's what's
actually in the code:

- **Deleting a profile doesn't delete anything.** It moves the profile
  to a trash folder first (`Restore User` brings it back), with a
  configurable retention window before it's gone for good.
- **The first time you use this**, if you already have real
  saves/savestates/RA login in place, they're folded into your first
  profile automatically — nothing is overwritten or discarded.
- **Switching profiles refuses to touch anything it doesn't
  recognize.** If `/media/fat/saves` (or savestates/inputs) isn't
  already a symlink this script manages, it stops and tells you instead
  of guessing.
- **Every destructive action needs a real confirmation, and every
  Yes/No prompt defaults to No** — a stray button press can't delete
  anything by accident.

It's also a single, plain bash script — no compiled binary, nothing
hidden — so you can read exactly what it does to your files before
running it, and it's licensed under the GPL so it stays that way.

## Why this exists

MiSTer itself has no concept of user accounts. If two people share a
MiSTer, they share one `retroachievements.cfg` (one RA login) and one set
of save files — whoever plays last overwrites the other's progress and
gets credited for the other's achievements.

This script doesn't change any of that at the MiSTer/core level. It just
manages **which** login, save files, and controller mappings are
currently "live" by swapping four things whenever you switch profiles:

- `/media/fat/retroachievements.cfg` — a per-profile copy
- `/media/fat/saves` — a symlink to a per-profile folder
- `/media/fat/savestates` — a symlink to a per-profile folder
- `/media/fat/config/inputs` — a symlink to a per-profile folder

Only one profile is active at a time — exactly as if only one login and
one set of saves existed, just swappable in a few seconds.

Each profile's folder is named by a stable internal ID (`User001`,
`User002`, ...), never by the display name you actually see and type —
the name lives in a small `.name` file inside that folder instead.
Renaming a profile only ever rewrites that one file; the folder and
every live symlink pointing at it are untouched. (An earlier version
used the display name as the folder name directly, so renaming meant
moving the whole folder and re-pointing the live symlinks to match —
that could silently leave saves pointing at a path the renamed profile
no longer tracked. Not possible anymore.)

## Requirements

- **RetroAchievements is not a stock MiSTer feature.** This script assumes
  odelot's RA-enabled fork of the main MiSTer binary, plus RA-modified
  cores (NES, SNES, Genesis/Mega Drive, SMS/Game Gear, GB/GBC, N64, PSX),
  are **already installed and working**. See
  [odelot/Main_MiSTer](https://github.com/odelot/Main_MiSTer) or
  [manyhats-mike/mister-fpga-retroachievements](https://github.com/manyhats-mike/mister-fpga-retroachievements).
  This script does **not** install RA support — it only manages the
  config/save files around it.
- A standard MiSTer setup with `/media/fat` as the root of the SD card.

## Install

1. Either place [`mister_profiles.sh`](Scripts/mister_profiles.sh) inside `Scripts` (`/media/fat/Scripts`) on your MiSTer SD card or add the following to `downloader.ini` on your SD card (or `/media/fat/downloader.ini`):
2. Run `update.sh` or `update_all.sh` to install the script if you added it to `downloader.ini`.

```ini
[BertSVG/MiSTer_FPGA_User_Profiles]
db_url = https://raw.githubusercontent.com/BertSVG/MiSTer_FPGA_User_Profiles/db/db.json.zip
```

Run it from the OSD: **F12 → Scripts → mister_profiles**. Launching it
shows a splash screen once — it auto-continues to the main menu after
3 seconds, or immediately on any keypress.

The very first time you create or switch to a profile, if
`/media/fat/saves`, `/media/fat/savestates`, `/media/fat/config/inputs`,
or `/media/fat/retroachievements.cfg` are still real files/folders (not
yet managed by this script), whatever's already there is automatically
folded into that profile instead of being overwritten or lost.

## What it looks like

The whole UI is a monochrome, boxed terminal menu (styled after old
CRT-monitor text screens), centered on the screen (both directions),
navigated with arrow keys or a controller mapped to arrow-key-equivalent
input. The selected item is shown on a solid colored background with
black text (can't show that in plain markdown, so it's just `[Select
User]` below). The color itself (green, yellow, white, red, blue,
magenta, or cyan) and its intensity (Bright or Dark) are both chosen from
**Settings → Menu Color**, shown here without the centering so it
fits on the page:

```
+------------------------------------------+
|                                          |
| +--------------------------------------+ |
| |  MiSTer User Profiles                | |
| |  Active User: Alex                   | |
| |  Active RA User: AlexRA              | |
| +--------------------------------------+ |
|                                          |
| +--------------------------------------+ |
| | [Select User]                        | |
| |  Manage Users                        | |
| |  Settings                            | |
| |  Quit                                | |
| +--------------------------------------+ |
|                                          |
|      Up/Down: Move    Enter: Select      |
|                                          |
+------------------------------------------+
```

## Main menu

A fixed 4 items, regardless of how many profiles exist:

- **Select User** — lists every existing profile plus Back. Picking one
  switches to it: relinks `saves`/`savestates`/`inputs`, copies its
  `retroachievements.cfg` into place, shows you the RA username that's
  about to go live, and asks you to confirm it's correct before offering
  a reboot (catches "copied the wrong profile's cfg" mistakes before they
  bite). Loops back to this same list after a switch, so trying a couple
  of profiles in a row doesn't mean re-entering the menu each time —
  "Back" is what returns you to the main menu.
- **Manage Users** — a flat list of actions (see below), not a profile
  picker.
- **Settings** — Menu Color and Trash Settings, grouped together (see
  below).
- **Quit** — exits. If a profile was actually switched (or an active
  profile's RA login was edited) during this session, offers a reboot so
  the RA-enabled binary picks up the new credentials cleanly; otherwise
  just exits, no reboot.

## Manage Users

Opens a flat action list — **Create User, Copy User, Rename User, Edit
RA Login, Set Wallpaper, Restore User, Delete User, Back** — instead of
picking a profile first. Every action loops back to this same list when
it's done, so you can do several things in one visit; only **Back**
returns to the main menu.

- **Create User** — prompts for a name, creates the profile, optionally
  offers to copy the currently active profile's controller mappings into
  it (handy when the new person is using the same physical controllers),
  optionally lets you enter that person's RA username/password right
  away, then switches to it.
- **Copy User** — asks which profile to copy, then the new name, then
  creates a full copy (saves, savestates, inputs, and RA login) under
  that name, without switching to it.
- **Rename User** — asks which profile, then the new display name (see
  the ID/name note above); nothing about where saves/savestates/inputs
  actually live ever moves, so this is safe to do on the active profile
  too.
- **Edit RA Login** — asks which profile, then changes just that
  profile's RA username/password without touching any other setting in
  `retroachievements.cfg`. If it's the active profile, refreshes the live
  config too.
- **Set Wallpaper** — asks which profile, then assigns one of your staged
  images as that profile's OSD wallpaper (see "Per-profile OSD wallpaper"
  below for the full picture, including the reboot and
  same-image-on-two-profiles warning).
- **Restore User** — lists every profile currently sitting in the trash
  (see Delete User), labeled by name and how long ago it was deleted, and
  moves the one you pick back into the active profile list. Shows "Trash
  is empty — nothing to restore." if there's nothing to bring back.
- **Delete User** — asks which profile, then after confirmation, moves it
  into a trash folder rather than deleting it immediately, so a mistaken
  deletion can still be recovered (see **Restore User** above, or
  "Trash Settings" to change how long it stays recoverable). If it was
  the active profile, clears the `saves`/`savestates`/`inputs` links so
  nothing points at a deleted folder. Sits last in this list, right above
  Back — it's the one destructive, rarely-used action here, so it's kept
  out of the way of the everyday ones above it.

## Settings

Groups the two menu-behavior options together, both loop until you pick
**Back**:

- **Menu Color** — one combined screen, not a submenu: a "Colors:"
  section label followed by the fixed color palette (Green, Yellow,
  White, Red, Blue, Magenta, Cyan), then a "Brightness:" section label
  followed by Bright or Dark — both indented under their own label, so
  they read as clearly grouped under it — then Back at the base level.
  Up/Down moves through the whole thing as one list (the two section
  labels aren't selectable — Up/Down skips straight over them). Picking
  any color or brightness applies it immediately and stays right there
  on the same screen — so you can step through Green, then Yellow, then
  Bright, then Dark, and so on, seeing each one live, without ever
  leaving. Only picking "Back" (deliberately) returns to Settings.
  Brightness affects both the theme's text color and the selected item's
  highlight background — Dark is the default and is confirmed to render
  cleanly on real hardware; Bright's highlight background is confirmed
  muddy on this console for every color, so Dark is the recommended
  choice — Bright is still offered, since text-only rendering (the
  color everywhere except the highlight) works fine either way. Both
  choices are remembered across runs.
- **Trash Settings** — the heading shows the current setting (e.g.
  "Current: 1 day"), so you don't need to already remember it. How long
  a deleted profile (see Delete User) stays recoverable before it's
  purged for good: 1, 3, 7, 14, or 30 days, or **Instant (no trash)** to
  go back to deleting immediately with no recovery window at all, plus
  **Back** to leave it unchanged. Defaults to 1 day. The choice is
  remembered across runs, and changing it prunes anything already
  overdue right away.

## Per-profile OSD wallpaper

Drop `.png` files into a shared staging folder by hand (e.g. via
SFTP/network share):

```
/media/fat/wallpapers/
```

Then use **Set Wallpaper** (under Manage Users → a profile) to assign
one of them to that profile — it's copied into
`/media/fat/profiles/<id>/menu.png`, and to the live
`/media/fat/menu.png` too if that profile is currently active (a reboot,
offered at Quit, is needed for it to actually show — MiSTer only reads
its wallpaper at OSD boot). If the image you pick is already used by
another profile, you're warned before assigning it — nothing dynamically
marks whose wallpaper is whose, so two profiles sharing one image would
otherwise look identical with no way to tell which one is actually
active. This script can't fetch or create an image itself, so getting
files into the staging folder is still a manual step, but once they're
there any profile can be assigned/reassigned from the menu without
needing SFTP again. A profile with no wallpaper set just leaves the
current one alone when switched to.

## Entering text without a keyboard

Anywhere the script needs typed text (profile name, RA username/password),
you get an on-screen keyboard: a character grid navigated with
Up/Down/Left/Right + Enter. Digits 1–9 sit in a 3×3 numpad-style block;
letters are alphabetical (not QWERTY). SHIFT toggles upper/lower case.
A physical keyboard still works here too — typing is appended directly,
so this is a hybrid: fast typing if you have a keyboard, full navigation
if you don't (there's no separate "Type Directly" prompt to choose
first — it goes straight to this screen either way). If your controller
has a dedicated Back button (sending a bare ESC, no physical Backspace
key on most controllers), it deletes the last character too — no need
to navigate to the grid's own `BKSP` cell every time.

Elsewhere in the script, that same controller Back button also works as
a shortcut for "go back": on any menu list it picks whatever "Back" or
"Cancel" already is, and on a Yes/No confirmation it answers "No" —
regardless of which item is currently highlighted. It's a no-op on the
main menu, since there's nowhere higher to go back to.

## Layout this script creates

```
/media/fat/profiles/<id>/.name                  <- display name (id is e.g. User001, User002)
/media/fat/profiles/<id>/retroachievements.cfg
/media/fat/profiles/<id>/saves/<CORE>/...
/media/fat/profiles/<id>/savestates/<CORE>/...
/media/fat/profiles/<id>/inputs/*.map
/media/fat/profiles/<id>/menu.png               <- set via "Set Wallpaper", optional
/media/fat/profiles/.current                    <- id of the active profile
/media/fat/profiles/.next_id                    <- counter for allocating the next id
/media/fat/profiles/.trash/<id>-<epoch>/        <- deleted profiles, see below
/media/fat/profiles/.trash_retention            <- saved "Trash Settings" choice, in days (0-30)
/media/fat/wallpapers/*.png                     <- staging folder, drop .png files in by hand
/media/fat/saves                                <- symlink to the active profile's saves
/media/fat/savestates                           <- symlink to the active profile's savestates
/media/fat/config/inputs                        <- symlink to the active profile's inputs
/media/fat/retroachievements.cfg                <- copy of the active profile's RA credentials
/media/fat/menu.png                             <- copy of the active profile's wallpaper, if any
```

### Recovering a deleted profile

A profile deleted while "Trash Settings" isn't set to Instant lands at
`/media/fat/profiles/.trash/<id>-<epoch>/` instead of being removed right
away. Use **Restore User** under Manage Users to bring it back — it'll
show up in the profile list again exactly as it was.

If you'd rather do it by hand (or the script isn't available), connect
over SFTP/network share and move that folder back to
`/media/fat/profiles/<id>/` (dropping the `-<epoch>` suffix) — same
result.

## Notes

- exFAT (what `/media/fat` is formatted as) is case-insensitive but
  case-preserving. A typo in the case of a **profile name** is harmless.
  A typo in the case of the **RA username** inside
  `retroachievements.cfg` is not — retroachievements.org logins are
  case-sensitive, and this script won't catch that for you beyond the
  "does this look right?" confirmation when switching.
- Every Yes/No prompt defaults to **No** — pressing Enter without moving
  the selection always picks the safer option, so a stray Enter press
  can't accidentally confirm something destructive like deleting a
  profile.
- Confirmed working on real MiSTer hardware: controller-driven navigation,
  the on-screen keyboard, screen centering across different resolutions,
  RA login switching, no cross-contamination of saves/savestates/RA
  login between profiles, first-run migration, profile display names,
  editing a non-active profile's RA login, wallpaper assignment
  (including the collision warning), the Delete User trash/Trash
  Settings feature, Restore User (including restoring the correct one
  out of two different deleted profiles), the confirmation dialog
  (correctly sized, word-wrapped, no duplication on Up/Down, and now
  matching the same nested double-border look every other screen has).
- Every status message (e.g. "Switched to profile 'X'", "Deleted 'X'
  (...)") and the "Press any key to continue..." prompt now sit inside
  that same nested double-border look too, instead of appearing as bare
  scrolling text, and long messages now word-wrap instead of silently
  truncating. Confirmed working on real hardware.
- The startup splash screen (title art in a bordered box, shown once
  before the main menu, auto-continuing after 3 seconds or immediately
  on a keypress) is confirmed working on real hardware.
- The selected-item highlight (a solid colored background with black
  text, replacing an earlier `>...<` bracket approach) is confirmed
  working on real hardware for Green in Dark mode. The other colors and
  Bright mode are offered as full choices but haven't each been
  individually confirmed to look as clean — this is a known tradeoff,
  not an oversight; pick whatever looks best to you.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
