# mo2-linux-nxm-handler

Fixes the "Mod Manager Download" button on Nexus Mods when you run Mod Organizer 2 (MO2) through Wine or Proton on Linux.

## The problem

You're a happy Linux gamer and you want to play some Skyrim. Modded, of course. So you set up a prefix, install the game, install MO2 inside it, and configure everything. Then you click "Mod Manager Download" on Nexus Mods and nothing happens. MO2 doesn't open, no download starts. Sad face :C

MO2 lives inside a Wine prefix, a fake little Windows install. When it claimed `nxm://` links for itself, that claim went no further than the prefix. Your real Linux desktop, the one your browser runs on, never got the memo.

This tool delivers the memo, then points each game's links at the MO2 install that should handle them.

## What you need

| Need | What it's for | Notes |
| --- | --- | --- |
| MO2 working under Wine or Proton | the thing this fixes | usually set up through Lutris |
| `xdg-utils` | registering `nxm://` with your desktop | almost every desktop ships it |
| `zenity` | the popups, when a link needs a decision | almost always installed |
| `gio` | handing a link to a different mod manager | ships with glib2, only needed for that case |
| UMU 1.4.1 or newer | reaching an MO2 that is already open | Proton setups only, Lutris 0.5.20 and up bundle it |

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

This changes nothing. It looks through your Lutris games, finds any MO2 installs, and lists each one with the Nexus game name it matched. Read the list and check your games are all there.

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

All three sit inside your home directory. Nothing goes system-wide and nothing asks for your password. `uninstall.sh` reverses all three.

## Checking it worked

Click a real "Mod Manager Download" button on Nexus Mods and see if MO2 pops up.

To test without a browser, run the handler yourself:

```
~/.local/share/mo2-linux-nxm-handler/bin/nxm-router.sh \
  'nxm://fallout4/mods/1/files/1?key=test&expires=9999999999'
```

Swap `fallout4` for one of your own games. The key in that link is fake, so MO2 will complain that the download failed. That's fine: the part being tested is whether the right MO2 opens or comes forward at all.

## Setups that need extra steps

> [!IMPORTANT]
> If MO2 runs under Proton, a link can only reach an MO2 that is **already open** when Lutris starts that game with `UMU_CONTAINER_NSENTER` set to `1`. `install.sh` checks for this and offers to add it for you. Without it, close MO2 before clicking a download.

<details>
<summary><b>Why that setting is needed, and how to add it by hand</b></summary>

Proton runs MO2 inside a sealed container. MO2 listens for "add this mod to downloads" on a channel that carries only inside that container, so a link has to be delivered from inside that same container.

UMU can step into a container that already exists rather than build a second one, but only if whoever built it left the door open. The handler leaves it open for any MO2 it starts itself. An MO2 you start from Lutris needs Lutris to do the same.

`install.sh` offers to make that change, keeping a `.bak` copy of any file it edits. Close Lutris first so it doesn't write the file back out from memory. To do it by hand: right click the game in Lutris, Configure, System options, Environment variables, add `UMU_CONTAINER_NSENTER` with the value `1`. Either way, restart MO2 afterward.

With the setting on, MO2 takes about five seconds longer to start, because it looks for an existing container before building one. In return, clicking a download while MO2 is open puts the mod straight into the window you already have open.

Plain Wine prefixes have no container, so none of this applies to them. Links reach a running MO2 on their own. The same goes for a handful of older or unusual Proton builds that run without a Steam runtime, Proton-Tkg among them: no container, nothing to step into, nothing to set. If you're unsure which kind you have, look for `require_tool_appid` in that Proton's `toolmanifest.vdf`. If it's there, the container applies and so does this section.

</details>

<details>
<summary><b>Which Proton builds work</b></summary>

Newer Lutris versions run a Proton game through a bundled tool called UMU instead of Lutris's own copy of Wine. The installer detects that and routes the link the same way Lutris launches the game, so those games need no extra setup.

This is not limited to GE-Proton. Valve's own Proton builds, UMU-Proton, and community builds like Proton-EM or Proton-Tkg all work. Whether you leave the runner on "GE-Proton (Latest)" or pin one exact build, the installer resolves the same Proton the game itself runs under.

</details>

<details>
<summary><b>My MO2 isn't in Lutris</b></summary>

If you run MO2 through a plain Wine prefix, Bottles, or anything else that isn't Lutris, `install.sh` won't find it on its own. Add it by hand.

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

Only one app can be the system default for `nxm://` links, so this tool gets the click first even for a game you handle with something else.

When it sees a game it has no MO2 install for, it offers to hand the link straight to any other installed app that also knows how to open `nxm://` links, rather than making you pick an MO2 install that doesn't apply. Say yes to "always send this game's links there" and it records the choice in `~/.local/share/mo2-linux-nxm-handler/fallback-routes.conf` and stops asking.

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

- no `nxmhandler.exe` sitting next to `ModOrganizer.exe`, meaning the MO2 install is incomplete
- no `ModOrganizer.ini` anywhere under the prefix, meaning MO2 has never actually been run for that game
- the runner couldn't be resolved, meaning Lutris is pointing at a Wine or Proton build that isn't installed any more

</details>
<br>
If none of that fits, open an issue with the version line, the log lines from the click, and the output of `install.sh --dry-run`.

## Removing it

```
~/.local/share/mo2-linux-nxm-handler/uninstall.sh
```

This removes the entry that told your browser how to open `nxm://` links, clears it as the default handler, and deletes the installed program files.

Your settings and log are deliberately left behind, so reinstalling later picks up where you left off: `routes.conf`, `manual-routes.conf`, `fallback-routes.conf`, `games.local.map` and `router.log`, all in `~/.local/share/mo2-linux-nxm-handler/`. Delete that folder yourself if you want it fully gone.

## License

Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International. Free to use and share, no commercial use allowed, and any fork or adaptation has to stay under this same license and stay free. See [LICENSE](LICENSE) for the full terms.
