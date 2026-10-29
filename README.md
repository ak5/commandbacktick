# CommandBacktick

Upgrade **Command + `** to switch between an app's windows across macOS desktops.
A native Swift/AppKit menu-bar app with no third-party dependencies.

Hold Command and tap ` to browse, add Shift to go backward, then release Command
to select. Escape cancels. Identified windows on the current desktop come first,
followed by the app's windows elsewhere.

With Stage Manager, other apps' windows in the visible group come first. Starting
from an editor grouped with a terminal gives: terminal → other local editor
windows → editor windows on other desktops. The starting app stays fixed during
that Command hold. Select the terminal and release Command; the next hold starts
with the grouped editor, then the terminal's other windows.

The overlay shows app icons, window titles, and optional browser profile pictures.
It joins other apps' Stage Manager groups and desktops. It does not capture window
thumbnails or require Screen Recording.

## Install from source

Requires macOS 14 or later and Xcode Command Line Tools with Swift 5.9 or later.
Install the tools with `xcode-select --install` if needed.

There are currently **no tags, releases, or prebuilt downloads**. Builds are signed
locally with an ad-hoc signature; Apple Developer ID signing and notarization are
not configured. You do not need a paid Apple Developer membership to build locally.

```sh
git clone https://github.com/ak5/commandbacktick.git
cd commandbacktick
nice -n 10 swift test --jobs 1
nice -n 10 ./scripts/build-app.sh
./scripts/install-app.sh
open "$HOME/Applications/CommandBacktick.app"
```

The installer quits CommandBacktick, installs a fresh bundle at
`~/Applications/CommandBacktick.app`, and keeps any previous build in a temporary
backup directory printed to the terminal. It does not launch the app or alter
permissions, login items, or macOS shortcuts. Use the installed copy, not the one
in `dist`, when granting permissions and enabling Launch at Login.

## First-time setup

The app starts paused. Use its **⌘`** menu-bar item to enable switching. The normal
menu contains switching, Permissions, Launch at Login, and Quit.

1. In **System Settings → Privacy & Security**, grant **Accessibility** to the
   installed app. On macOS 27 this permission is named **Device Control and Data
   Access**. It allows reading and activating application windows.
2. Grant **Input Monitoring** when requested. CommandBacktick checks Command and
   Escape while the switcher is open; it does not record typed text. Relaunch if
   macOS requests it, then choose **Enable Command–`** again.
3. Disable any other utility handling the same shortcut. With Stage Manager,
   also disable **Move focus to next window** under **System Settings → Keyboard
   → Keyboard Shortcuts → Keyboard**. Native group cycling can interfere even
   with exclusive registration. CommandBacktick does not change that preference.
4. If you use Chrome, allow **Automation → Google Chrome** when requested, then
   retry the shortcut. This lists and activates browser windows on other desktops.
5. Enable **Launch at Login** from the menu if desired.

Test a few windows on one desktop and another on a second desktop. Keep Command
held through several taps, release to select, and try again on the destination
desktop. For Stage Manager, also test a group containing two different apps.

If you pause or quit CommandBacktick after disabling the native binding, Command–`
will not switch windows. Restore **Move focus to next window** when uninstalling.

## Updating and permission troubleshooting

Pull the source, rebuild, and run the installer again:

```sh
git pull --ff-only
nice -n 10 ./scripts/build-app.sh
./scripts/install-app.sh
```

Ad-hoc signatures change when the executable changes. An enabled permission
entry may still refer to the previous build. If the app says permission is missing:

1. Leave CommandBacktick closed. Quit and reopen System Settings.
2. In Accessibility / Device Control and Data Access, remove its entry with **−**.
3. Click **+**, press **Command–Shift–G**, enter
   `~/Applications/CommandBacktick.app`, add it, and enable its toggle.
4. Open the installed app and choose **Enable Command–`**. If Input Monitoring or
   Chrome Automation is also requested, approve that permission and relaunch.

If removing and re-adding still leaves a stale Accessibility entry, quit the app
and reset **only its** approval before repeating those steps:

```sh
tccutil reset Accessibility com.ak5.commandbacktick
```

Do not overwrite the running executable in place. The installer replaces the
whole bundle to avoid reusing a cached signing identity. Permission grants must
still be approved in System Settings.

## Multiple Chrome profiles

Profile pictures are discovered from Chrome's local `Local State` metadata and
account image files. No separate config or exported mapping is needed.

Use Chrome's **Window → Name Window** feature to name each window with its exact
profile display name, for example `Sam` or `Sam (Work)`. Name new windows the same
way. Windows of the same profile may share a name. Update window names if you
rename a profile. Full Accessibility titles are used when available, but explicit
window names allow matching on other desktops.

macOS may separately ask to read Chrome's protected data. Allow this for profile
pictures. Unknown or conflicting names, unreadable files, and built-in avatar
artwork fall back to the app icon. Only Chrome's standard user-data directory is
supported; custom directories and other browser profile formats are not.

Profile data stays on the machine. The app makes no network requests and does
not export profiles, record typed text, or log window titles or pictures. Do not
include private profile data or real window titles in bug reports.

## Compatibility

Apps are detected dynamically; there is no app allowlist. Chrome uses stable
browser window IDs through Apple Events. Other apps use Accessibility and an
English **Window** menu for windows on other desktops. Menus are re-read before
activation; an ambiguous changed list fails safely. Without that menu, switching
is limited to the windows the app exposes through Accessibility.

Current-desktop ordering is best effort for invisible windows or identical
titles. Stage Manager peers are inferred from visible standard windows on the
starting window's display, matched to Accessibility bounds. macOS exposes no
public Stage Manager group identifier. Minimized and thumbnail surfaces are
excluded from the group. Without Stage Manager, cycling stays within one app.

Generic cross-desktop support depends on each app's accessibility implementation.
Full-screen apps, multiple displays, non-US keyboard layouts, and Secure Input
need broader testing. The shortcut uses the physical grave-key position on a US
keyboard. The app uses public macOS APIs and does not change SIP or desktop
assignments.

## Development and diagnostics

```sh
nice -n 10 swift test --jobs 1
nice -n 10 python3 -m unittest discover -s Tests/Installation -p 'test_*.py'
```

The tests cover window ordering, direction changes, Command-release confirmation,
menu resolution, profile matching, safe image paths, and installer rollback.
They do not prove macOS permissions or real desktop transitions; use the manual
checks above after changing window behavior.

To show the **Diagnostics** submenu, quit the app, then launch with `--debug`:

```sh
open "$HOME/Applications/CommandBacktick.app" --args --debug
```

It contains a synthetic interface preview and the last switching error. Quit and
reopen normally to hide it. Debug mode does not enable event or window logging.
Errors still appear as alerts during normal use, and Permissions stays available.

Additional explicit diagnostic commands:

```sh
"$HOME/Applications/CommandBacktick.app/Contents/MacOS/CommandBacktick" --diagnose
"$HOME/Applications/CommandBacktick.app/Contents/MacOS/CommandBacktick" --render-preview /tmp/commandbacktick-preview.png
```

`--diagnose` checks the process invoking it; macOS can attribute terminal-launched
processes differently. The running app's **Permissions** dialog is authoritative
for that app instance. The preview uses synthetic titles and does not capture
your screen.

## License

[MIT](LICENSE).
