# Clawd's Lair

A small macOS app (window + menu bar) for switching the Claude desktop app between accounts without signing out, plus per-account usage stats.

> Clawd's Lair is an unofficial, community-made tool. It is not affiliated with, endorsed by, or supported by Anthropic. "Claude" is a trademark of Anthropic.

## Features

- **Switch accounts instantly.** Keep several Claude accounts signed in and swap between them from the window, the menu bar, or a global hotkey.
- **Per-account stats.** Tokens, models, plan usage and an activity calendar for each account, all read from files already on your Mac.
- **Lives in the menu bar.** Opens at login and stays out of the Dock unless a window is open.
- **Safe by design.** Claude is always asked to quit normally, swaps are rolled back if anything fails, and removed accounts go to the Trash.

## Requirements

- macOS 26 or later (the UI uses Liquid Glass), on Apple silicon or Intel
- The Claude desktop app

## Install

1. Download `Clawds-Lair-<version>.zip` from the [latest release](https://github.com/BuflPlayz/Clawds-Lair/releases/latest) and unzip it.
2. Move `Clawd's Lair.app` to your Applications folder.
3. Open it. The app isn't notarized by Apple, so macOS blocks it the first time. Go to **System Settings → Privacy & Security**, scroll down to the message about Clawd's Lair, and click **Open Anyway**.

It adds itself to Login Items the first time it runs from Applications; you can turn that off in its Settings.

### Build it yourself

You need Xcode 26 or later.

```bash
git clone https://github.com/BuflPlayz/Clawds-Lair.git
```

```bash
cd Clawds-Lair && ./scripts/build-app.sh --install
```

This puts `Clawd's Lair.app` in `~/Applications`.

## How it works

Signed Claude builds always use `~/Library/Application Support/Claude` and ignore any custom-folder setting. So each account gets its own copy of that folder, and switching swaps them:

1. Claude is asked to quit normally (it is never force-killed).
2. The current `Claude` folder is renamed to `~/Library/Application Support/ClaudeSwitcher/Profiles/<id>`.
3. The chosen account's folder is renamed to `Claude`.
4. Claude is reopened.

These are renames on the same disk, so nothing is copied or downloaded and switching is instant. If something fails partway through, the first rename is rolled back. On every launch the app also works out which account is in Claude's folder by looking at the disk, so an interrupted swap can't confuse it.

A new account starts with an empty folder. Claude opens on it and you sign in once. The first time you use Claude Code or Cowork there, Claude downloads its own copy of those tools (Cowork's VM is about 11 GB).

## Stats

Read locally, nothing is sent anywhere:
- Tokens and models: Claude Code and Cowork transcripts (`~/.claude/projects` and each Cowork session folder), counted per account.
- Plan usage (5-hour and weekly %): the latest sample Claude saved in that account's `plan-usage-history.json`.
- Regular chats live on Claude's servers, so they aren't counted.
- Profile pictures: copied out of each account's own Claude cache (`Cache/Cache_Data`) into `~/Library/Application Support/ClaudeSwitcher/Avatars`, so nothing is downloaded. An account Claude hasn't shown a picture for gets its initial instead.

## Removing an account

Remove moves that account's folder to the Trash (it can be restored from there). You can't remove the account that is currently in Claude's folder; switch away from it first.

## Look and feel

The look borrows from Claude itself, without shipping any of Claude's artwork. The first time the app runs (and again whenever Claude updates), it copies Claude's animated spark sprites and Clawd's pixel-art animations (from Claude's Clawd Quest game) out of your own `Claude.app` into `~/Library/Application Support/ClaudeSwitcher/ClaudeArt`. At launch it also loads Anthropic Sans/Serif from `Claude.app`. Without Claude.app it falls back to system fonts and icons.

The app icon (`Resources/AppIcon.icon`, an Icon Composer document) and the menu bar icon are original: a lair with two eyes looking out.

## Releasing

```bash
./scripts/build-app.sh --zip
```

builds a universal app and packages it as `build/Clawds-Lair-<version>.zip`, ready to attach to a GitHub release. Bump `VERSION` in `scripts/build-app.sh` first. The app is signed ad hoc, not with a Developer ID, which is why people have to click Open Anyway.

## Development

```bash
swift test
```

runs the swap tests against throwaway folders (plus a test that copies the art out of Claude.app, if it's installed), and

```bash
swift run ClawdsLair --dump-stats
```

prints every account's stats as JSON without opening any UI.

The app was first called ClaudeSwitcher, which is why its data lives in `~/Library/Application Support/ClaudeSwitcher`.

## License

[MIT](LICENSE)
