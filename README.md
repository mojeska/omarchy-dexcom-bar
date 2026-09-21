# omarchy-dexcom-bar

A [Dexcom Share](https://www.dexcom.com/) blood glucose readout for the
[Omarchy](https://omarchy.org/) bar. Shows the current value and trend
arrow, colored **orange** above your high threshold and **red** below your
low threshold.

This only works with a **Dexcom** continuous glucose monitor (CGM) and its
Dexcom Share service -- it has no support for other CGM brands. It is an
independent, unofficial project, not an application provided by, affiliated
with, or endorsed by Dexcom, Inc.

## Requirements

- Omarchy (the Quickshell-based bar and its plugin system)
- Python 3 (standard library only, no extra packages)
- A Dexcom account with **Dexcom Share enabled and at least one follower
  added** in the Dexcom mobile app -- the Share API returns nothing if the
  account isn't actively being followed by someone

## Install

```bash
git clone <this-repo-url> omarchy-dexcom-bar
cd omarchy-dexcom-bar
./install.sh
```

This installs `omarchy-dexcom-status` to `~/.local/bin`, installs the bar
widget (including its settings panel) to
`~/.config/omarchy/plugins/dexcom-glucose`, creates
`~/.config/omarchy/dexcom.json` (permissions `600`) if it doesn't already
exist, and enables the widget in the right section of your bar.

**Left-click the widget** to open its settings panel and enter:

- **Username / password**: your regular Dexcom account login (the one used
  in the Dexcom mobile app, for the account that's actually wearing the
  sensor -- not a follower account), not a separate API key. If you log in
  with a US phone number, it needs the country code (`+15551234567`, not
  `5551234567`) -- Dexcom Share rejects a bare 10-digit number with the same
  generic error as a wrong password, which makes it easy to chase the wrong
  problem. `omarchy-dexcom-status` auto-adds `+1` to a bare 10-digit
  username when region is US, so you likely don't have to think about this,
  but it's worth knowing if login still fails. Leave the password field
  blank to edit the other fields without changing it.
- **Region**: US or outside-US.
- **High / low thresholds**: mg/dL cutoffs for orange/red.

The password is stored in the system keyring (`secret-tool` / Secret
Service -- served by `gnome-keyring`, a hard dependency of Omarchy itself,
so this works out of the box on every install), never written to disk.
`dexcom.json` only holds the username, region, and thresholds, still locked
to `600`. **Middle-click the widget** any time afterward to reopen the
settings panel and change any of this.

If you're upgrading from a version where `dexcom.json` had a plaintext
`password` field, nothing needs to be re-entered -- the next successful
poll migrates it into the keyring and rewrites the file without it,
automatically.

## Use

The bar shows the value and a trend arrow, e.g. `118→`, `220↑` (orange),
`62↓` (red). A low reading also blinks the number in Morse SOS (··· --- ···)
so it's hard to miss out of the corner of an eye. It dims if a reading is
more than 20 minutes stale (sensor or network issue). Left-click forces an
immediate refresh (or opens the settings panel if not configured yet);
middle-click always opens the settings panel; right-click sends a desktop
notification with the full detail. The poll interval defaults to 60 seconds
and can be changed with:

```bash
omarchy bar set dexcom-glucose refreshSeconds 120
```

## A note on failed logins

Dexcom Share will lock an account out if it sees repeated failed logins in
a short window, so `omarchy-dexcom-status` backs off after 3 consecutive
authentication failures and stops calling the API until you save the
settings panel again (it tracks `dexcom.json`'s mtime, which any save
touches, even a password-only change). If the bar just shows "Dexcom" with
no value, check the tooltip or run `omarchy-dexcom-status` directly in a
terminal to see the specific error.

Failure modes worth knowing about, all confirmed against a real account
while building this:

- **"login failed" (`AccountPasswordInvalid`) despite a correct password,
  when `username` is a bare 10-digit US phone number.** Dexcom Share
  requires the country code (`+15551234567`) and rejects a bare number with
  the exact same generic error as a wrong password -- there's no way to
  tell the two apart from the error alone. `omarchy-dexcom-status` now
  auto-adds `+1` for a 10-digit `username` when `region` is `"us"`, so this
  should be handled automatically; it's documented here in case you're
  troubleshooting an older version or a non-US-formatted number.
- **"login failed" for other reasons.** Dexcom Share's login can be on an
  older backend than the main Dexcom/Clarity web login, and the two
  sometimes drift out of sync -- a password that works on dexcom.com isn't
  guaranteed to work here. If phone formatting isn't the issue, try
  Settings → Share in the Dexcom mobile app and re-confirm/re-enter the
  password there, or do a full password reset (not just re-entering what
  you believe the current one is).
- **"no recent readings" despite a successful login.** This is Dexcom Share
  deliberately withholding data: the API only returns glucose values while
  the account has at least one *active, accepted* follower. Add one (or
  keep a spare Follow account around just for this) in the Dexcom app's
  Share/Manage Followers settings.

## Uninstall

```bash
./uninstall.sh
```

Removes the plugin and the helper script. Your `~/.config/omarchy/dexcom.json`
and your Dexcom password in the system keyring are both left in place --
remove them yourself if you're done with it:

```bash
rm ~/.config/omarchy/dexcom.json
secret-tool clear service omarchy-dexcom-bar account dexcom-share
```

## macOS (xbar)

`macos-xbar/dexcom-glucose.60s.py` is a self-contained port for
[xbar](https://xbarapp.com/) (or [SwiftBar](https://swiftbar.app/)) --
same Dexcom Share logic, same orange/red thresholds, same failure modes
and fixes described above, just packaged as a single script instead of
an Omarchy plugin since there's no Quickshell bar on macOS.

It does **not** blink SOS on a low reading like the Omarchy widget does --
that needs sub-second updates, which on macOS means SwiftBar's "streamable"
plugin type (a persistent process, not the run-and-exit model xbar plugins
normally use). Deliberately skipped to keep this script working the same
way on both xbar and SwiftBar rather than forking behavior between them.

Install:

1. Install xbar (or SwiftBar) and note its plugins folder (xbar asks for
   one on first launch; default is `~/Library/Application Support/xbar/plugins`).
2. Copy the script there and make it executable:
   ```bash
   cp macos-xbar/dexcom-glucose.60s.py "$HOME/Library/Application Support/xbar/plugins/"
   chmod +x "$HOME/Library/Application Support/xbar/plugins/dexcom-glucose.60s.py"
   ```
3. Click it in the menu bar → **Edit config…** to open
   `~/.config/dexcom-bar/dexcom.json` (created automatically on first run,
   permissions `600`) and fill in:
   ```json
   {
     "username": "",
     "password": "",
     "region": "us",
     "highThreshold": 180,
     "lowThreshold": 70
   }
   ```
   Same field meanings as the Omarchy version's settings panel (see
   Install above) -- unlike there, this file does hold the password in
   plaintext, since there's no in-app settings UI or keyring integration
   for the macOS port (see the note above on why the SOS blink is also
   skipped here; same reasoning -- not yet scoped as separate work).

The `.60s.` in the filename is how xbar knows to refresh it every 60
seconds -- rename the file (e.g. `.2m.`) to change that. Click **Refresh**
in the dropdown to force an immediate check.
