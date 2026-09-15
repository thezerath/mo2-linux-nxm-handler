# mo2-linux-nxm-handler

Fixes the "Mod Manager Download" button on Nexus Mods when you run Mod Organizer 2 (MO2) through Wine or Proton on Linux.

## The problem

You're a happy Linux gamer and you want to play some Skyrim. Modded, of course. So you set up a prefix, install the game, install MO2 inside it, and configure everything. Then you click "Mod Manager Download" on Nexus Mods and nothing happens. MO2 doesn't open, no download starts. Sad face :C

MO2 lives inside a Wine prefix, a fake little Windows install. When it claimed `nxm://` links for itself, that claim went no further than the prefix. Your real Linux desktop, the one your browser runs on, never got the memo.

This tool delivers the memo, then points each game's links at the MO2 install that should handle them.

## What you need

| Need | What it's for | Notes |
| --- | --- | --- |
| MO2, running under Wine or Proton | why we are all here | usually set up through Lutris |
| `xdg-utils` | registering `nxm://` with your desktop | usually preinstalled, but not on Arch |
| `zenity` | the popups, when a link needs a decision | usually already installed |
| `gio` | handing a link to a different mod manager | ships with glib2, only needed for that case |
| UMU 1.4.1 or newer | reaching an MO2 that is already open | Proton setups only, Lutris 0.5.20+ bundles it |

## Getting it

If you have git:

```
git clone https://github.com/thezerath/mo2-linux-nxm-handler.git
cd mo2-linux-nxm-handler
```

If you don't, open the [latest release](https://github.com/thezerath/mo2-linux-nxm-handler/releases/latest), download "Source code (zip)", unzip it, and open a terminal in the unzipped folder.

## Installing it

**1. See what it finds.**

```
./install.sh --dry-run
```

This changes nothing. It scans your Lutris library for MO2 installs and pairs them with Nexus Mods matches. Check if anything is missing or looks wrong.

**2. Install for real.**

```
./install.sh
```

**3. Delete the folder you downloaded.**

The installer copies everything it needs into `~/.local/share/mo2-linux-nxm-handler/`, so nothing points back at the folder once it finishes.

That's it. Nexus download buttons should now open the right copy of MO2.

If you use MO2 for several games, each in its own Wine prefix, there is nothing extra to do. Nexus puts the game name in the link and this tool reads it, so every click finds its own MO2.

To pick up a new game later, run the installed copy:

```
~/.local/share/mo2-linux-nxm-handler/install.sh
```

It's safe to run again and again. `--help` lists the options. `--version` prints the version, which is worth quoting in a bug report.

## What it installs

| Where | What it is |
| --- | --- |
| `~/.local/share/mo2-linux-nxm-handler/` | the program itself, with your settings and log alongside it |
| `~/.local/share/applications/mo2-linux-nxm-handler.desktop` | tells your desktop that something here opens `nxm://` links |
| `~/.config/mimeapps.list` | one line naming that shortcut as the default for `nxm://` |

All three sit inside your home directory. No sudo required. `uninstall.sh` reverses all three.

## Checking it worked

Click a real "Mod Manager Download" button on Nexus Mods and see if MO2 pops up.

To test without a browser, run the handler yourself:

```
~/.local/share/mo2-linux-nxm-handler/bin/nxm-router.sh \
  'nxm://fallout4/mods/1/files/1?key=test&expires=9999999999'
```

Swap `fallout4` for one of your own games. The key in that link is fake, so MO2 will complain that the download failed. That's fine, just checking if the right MO2 shows up.

## Setups that need extra steps

> [!IMPORTANT]
> Running MO2 through Proton? A download link only reaches MO2 if it's **already open**, and only if Lutris starts that game with `UMU_CONTAINER_NSENTER` set to `1`. `install.sh` offers to set that for you. Otherwise, a link only works if MO2 is closed when you click it.

<details>
<summary><b>Why that setting is needed, and how to add it by hand</b></summary>

Proton runs MO2 in a sealed container. MO2 only listens for new downloads inside that container, so the link has to be delivered from inside it too.

UMU can hop into an existing container instead of spinning up a new one, but only if the door's left open. This handler leaves it open for any MO2 it launches itself. If Lutris launches MO2 instead, Lutris needs that same setting.

**Close Lutris first, or it'll overwrite the change from memory.** Then run `install.sh` to set this for you (it backs up any file it touches). By hand: right click the game → Configure → System options → Environment variables → add `UMU_CONTAINER_NSENTER` with value `1`. Restart MO2 either way.

Adds about five seconds to MO2's startup while it checks for an existing container. Worth it: downloads now land straight in the MO2 window that's already open.

Plain Wine prefixes skip all this, no container means links reach MO2 directly. Same for a few Proton builds without a Steam runtime, like Proton-Tkg. Not sure which you've got? Check that Proton's `toolmanifest.vdf` for `require_tool_appid`. Found it? This section applies to you.

</details>

<details>
<summary><b>Which Proton builds work</b></summary>

Newer Lutris runs Proton games through UMU instead of its own Wine. The installer detects this and routes links the same way Lutris launches the game, no extra setup needed.

Works with more than GE-Proton: Valve's own builds, UMU-Proton, Proton-EM, Proton-Tkg, all of it. Pin a specific build or leave it on "GE-Proton (Latest)", the installer matches whatever Proton the game actually runs.

</details>

<details>
<summary><b>My MO2 isn't in Lutris</b></summary>

Running MO2 through a plain Wine prefix, Bottles, or anything that isn't Lutris? `install.sh` can't find it on its own, add it by hand.

After your first install, open:

```
~/.local/share/mo2-linux-nxm-handler/manual-routes.conf
```

and add one line per MO2 install:

```
nexus_domain|wine_binary|wine_prefix|nxmhandler_path
```

| Field | What goes in it |
| --- | --- |
| `nexus_domain` | the short game name Nexus uses in links, such as `skyrimspecialedition` or `fallout4` |
| `wine_binary` | full path to the `wine` or `wine64` for that install. For a Proton game use `umu:GE-Proton`, or `umu:` plus the absolute path to one specific Proton directory if you want a fixed build |
| `wine_prefix` | full path to that install's Wine prefix |
| `nxmhandler_path` | full path to `nxmhandler.exe` inside your MO2 folder |

Then run `~/.local/share/mo2-linux-nxm-handler/install.sh` to pick up the change. A manual entry always wins if it clashes with something auto-detected.

</details>

<details>
<summary><b>My game isn't recognized</b></summary>

If `install.sh` finds your MO2 install but can't work out which Nexus game it belongs to, it says so at the end and points you at `games.local.map`. Create this file:

```
~/.local/share/mo2-linux-nxm-handler/games.local.map
```

and add one line:

```
Exact Game Name From MO2|nexus_domain
```

Then run `~/.local/share/mo2-linux-nxm-handler/install.sh` again. The file is never touched by the installer or the uninstaller, so your entries survive reinstalls and upgrades.

</details>

<details>
<summary><b>A game I manage with a different mod manager</b></summary>

Only one app can own `nxm://` links system-wide, so this tool always gets the click first, even for games you manage elsewhere.

No MO2 install for that game? It offers to hand the link to any other app that opens `nxm://` links, instead of forcing you to pick an MO2 that doesn't fit. Say yes to "always send this game's links there" and it's saved to `fallback-routes.conf`, no more asking.

</details>

## Something's not working

Every click, real or test, gets written to a log file:

```
~/.local/share/mo2-linux-nxm-handler/router.log
```

Open it and read the lines from your last click. Each click starts with a line naming the version, so quote that if you report a problem. Then find your symptom.

<details>
<summary><b>Nothing happens, and the log has no new lines</b></summary>

The click never reached this tool. Check who owns `nxm://` links:

```
xdg-mime query default x-scheme-handler/nxm
```

It should answer `mo2-linux-nxm-handler.desktop`. If it names something else, another app has taken the default; run `install.sh` again to take it back. If it answers nothing, the install didn't finish.

Firefox also keeps its own separate choice. Check Settings, General, Applications for an `nxm` row and set it to "Always ask" if it points somewhere odd.

</details>

<details>
<summary><b>MO2 opens, but it's the wrong game's MO2</b></summary>

Two of your games resolved to the same Nexus name. Open `~/.local/share/mo2-linux-nxm-handler/routes.conf`, which holds one line per game, and look at the first field on each line.

Manual entries always beat auto-detected ones, so if you added something to `manual-routes.conf` earlier, that is the one in charge.

</details>

<details>
<summary><b>The log says <code>no MO2 route for domain=</code></b></summary>

The tool doesn't know that game.

If you do manage it with MO2, run `install.sh` again. If it still doesn't appear, the installer will say why under "Skipped instances".

If you manage that game with a different mod manager, the popup that follows lets you hand its links over permanently.

</details>

<details>
<summary><b>The log says <code>rejected malformed domain</code> or <code>ignoring non-nxm link</code></b></summary>

What arrived wasn't a normal Nexus mod link. Copy the link out of your browser and check it begins with `nxm://` followed by a game name.

</details>

<details>
<summary><b>MO2 is already open and the download never arrives</b></summary>

Expected when that MO2 was started without the container setting, and the popup you get says as much. See "Why that setting is needed" above.

</details>

<details>
<summary><b>The installer skipped one of my games</b></summary>

The "Skipped instances" list gives a reason per game. The usual ones:

- no `nxmhandler.exe` next to `ModOrganizer.exe`, meaning the MO2 install is incomplete
- no `ModOrganizer.ini` under the prefix, meaning MO2 has never been run for that game
- the runner couldn't be resolved, meaning Lutris points at a Wine or Proton build that's no longer installed

</details>
<br>
If none of that fits, open an issue with the version line, the log lines from the click, and the output of `install.sh --dry-run`.

## Removing it

```
~/.local/share/mo2-linux-nxm-handler/uninstall.sh
```

This removes the `nxm://` browser entry, clears it as the default handler, and deletes the installed program files.

Your settings and log are deliberately left behind in `~/.local/share/mo2-linux-nxm-handler/`, so reinstalling later picks up where you left off:

- `routes.conf`
- `manual-routes.conf`
- `fallback-routes.conf`
- `games.local.map`
- `router.log`

Delete that folder yourself if you want it fully gone.

## License

Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. Free to use and share, no commercial use allowed, and any fork or adaptation has to stay under this same license and stay free. See [LICENSE](LICENSE) for the full terms.
