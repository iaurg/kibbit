<p align="center">
  <img src="docs/logo.png" width="128" alt="Kibbit logo">
</p>

<h1 align="center">Kibbit</h1>

<p align="center">
  A pixel-art pet that lives in the macOS menu bar and answers quick questions using your Claude subscription, so you don't have to leave your terminal or editor.
</p>

<p align="center"><i>kibble + kibitz: a pet that chimes in with answers.</i></p>

<p align="center">
  <a href="https://github.com/iaurg/kibbit/actions/workflows/ci.yml"><img src="https://github.com/iaurg/kibbit/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="446" alt="Kibbit demo: hatching a legendary axolotl, connecting Claude, testing the hotkey, asking a question from the menu bar, and rerolling colors">
</p>

<p align="center">
  <img src="docs/pets.png" width="720" alt="All 7 pets across random color seeds and animation frames">
</p>

- 7 pets: cat, dog, bunny, frog, penguin, ghost, axolotl
- Colors are generated from a random seed (`#XXXX-XXXX`). Reroll to hatch a new palette. About 15% of seeds are **rare** and 3% are **legendary**.
- Animated: idle breathing, blinking, a thinking bounce, typing, a heart when an answer finishes, and sleeping after 10 minutes idle.
- A tiny chat with streamed answers, copyable code blocks, and an optional clipboard attachment for context.
- The energy bar shows how much of your 5-hour subscription window is left.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/iaurg/kibbit/main/install.sh | bash
```

That downloads the latest release, checks its SHA-256, puts `Kibbit.app` in `/Applications` and opens it. Setup takes it from there, including installing and signing in to Claude Code if you haven't yet.

- **Requires:** macOS 14 or newer, on Apple Silicon or Intel, and a Claude Pro or Max plan.
- **Update:** run the same command again.
- **Specific version:** `curl -fsSL https://raw.githubusercontent.com/iaurg/kibbit/main/install.sh | KIBBIT_VERSION=v0.1.0 bash`
- **Uninstall:** `curl -fsSL https://raw.githubusercontent.com/iaurg/kibbit/main/install.sh | bash -s -- --uninstall`

<details>
<summary>Why a script instead of a download link?</summary>

Kibbit is open source and isn't notarized by Apple. When a browser downloads an app, it marks it as quarantined, and macOS then refuses to open it until you approve it in System Settings. `curl` doesn't add that mark, so the script's install opens normally. [Read the script](install.sh) before running it; it's short.

If you prefer to download the zip from [Releases](https://github.com/iaurg/kibbit/releases) yourself, clear the quarantine mark after unzipping:

```bash
xattr -dr com.apple.quarantine /Applications/Kibbit.app
```
</details>

## First launch

Kibbit opens a short setup the first time it runs:

1. **Hatch** your egg. The species and colors are random. You can copy a share card to show it off.
2. **Connect Claude.** Kibbit checks that Claude Code is installed and signed in. If something is missing, one button opens Terminal with the official installer or `claude auth login` already running, and the page updates on its own when you're done.
3. **Try the hotkey.** Press it once to prove it works. If another app (Claude Desktop, ChatGPT and Raycast often use `⌥ Space`) catches it first, pick a different one.
4. **Done.** Launch at login is on by default.

To run setup again, right-click the pet and choose **Run Setup…**, or use the button in Settings.

## Use

| Key | Action |
| --- | --- |
| `⌥ Space` | summon / dismiss from anywhere (changeable in Settings) |
| `↩` | send |
| `⌘⇧V` | attach clipboard as context |
| `⌘.` | stop the answer |
| `⌘N` | new chat |
| `⌘,` | settings |
| `esc` | back to work |

Right-click the pet in the menu bar for a menu.

## How it talks to Claude

Kibbit doesn't call the API directly. It keeps one warm `claude -p` process running in stream-JSON mode, so it uses exactly the same auth as Claude Code (your subscription login). Because the process is already running, the first token arrives in about 1 second instead of the roughly 4 seconds a cold start takes. The process runs with no tools, no MCP servers, and no user settings or hooks, using a short "answer tersely" system prompt. `ANTHROPIC_API_KEY` is removed from its environment so nothing gets billed to an API key by accident.

If Claude Code isn't signed in on this machine, run `claude setup-token` and paste the token in Settings. It's stored in the Keychain.

The warm process shuts down after 15 idle minutes. Your next question resumes the same conversation with `--resume`.

## Development

Building from source needs the Swift toolchain. The Command Line Tools are enough; you don't need Xcode.

```bash
./scripts/build-app.sh               # → build/Kibbit.app
./scripts/build-app.sh --install     # → /Applications/Kibbit.app and launch
UNIVERSAL=1 ./scripts/build-app.sh   # Apple Silicon + Intel, as releases are built
swift build
./scripts/test.sh                                    # Swift Testing suite
.build/debug/Kibbit --render-gallery /tmp/pets.png   # all pets × seeds × animation frames
open build/Kibbit.app --args --ask "question"        # smoke test: opens the panel and sends
```

Sprites live in `Sources/Kibbit/Pets.swift` as the left halves of 16×16 grids, mirrored when drawn.

### Tests

`./scripts/test.sh` works with Xcode or with only the Command Line Tools. The suite covers:

- **Sprites and palettes:** every pet grid is well-formed and symmetric, all animation frames stay on the canvas, seeds are deterministic, and the rarity odds (3% legendary, 15% rare) hold.
- **Stream parsing:** the `claude` stream-JSON output, including lines split across chunks and error results.
- **Process lifecycle:** runs against [`Tests/KibbitTests/Fixtures/fake-claude`](Tests/KibbitTests/Fixtures/fake-claude), a stand-in CLI, so no Claude login is needed. Covers streaming, stop, crash recovery, `--resume`, model switches, and the launch flags that keep tools, memory and API keys out.
- **Chat flow:** send, answer, error, stop and new chat through the real view model.

### CI/CD

- **[CI](.github/workflows/ci.yml)** runs on every pull request and every push to `main`. It:
  - runs the tests
  - builds a universal `Kibbit.app` and checks its Info.plist, architectures and code signature
  - launches the release binary
  - installs and uninstalls the packaged zip with `install.sh`
  - runs shellcheck on every script
- **[Release](.github/workflows/release.yml)** runs when a `v*` tag is pushed. It repeats those checks and then publishes `Kibbit.zip` and `Kibbit.zip.sha256` to GitHub Releases, which is where `install.sh` downloads from:

  ```bash
  git tag v0.1.0 && git push origin v0.1.0
  ```

## License

[MIT](LICENSE)
