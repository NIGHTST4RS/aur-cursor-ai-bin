# AUR Cursor AI Binary Package Updater

Automated maintenance system for the `cursor-ai-bin` AUR package. This repository monitors Cursor IDE releases and keeps an AUR-ready `PKGBUILD` updated.

## What this repository does

This project is an automation repo, not a manual install guide. It:

- Checks for new Cursor stable releases on a schedule.
- Updates `PKGBUILD` version, commit, and source checksum.
- Publishes updates to AUR from `main`.
- Uses Cursor's bundled runtime from the upstream `.deb` package to avoid system-Electron mismatch issues that can break Git/containers/Remote SSH.
- Installs a `cursor` launcher wrapper that loads `~/.config/cursor-flags.conf` and delegates to Cursor's upstream launcher.
- Pins third-party GitHub Actions to immutable commit SHAs.
- Validates update API `version`/`commit` formats before generating package updates.
- Uses Dependabot to keep pinned GitHub Actions dependencies updated.

## Install (end users)

```bash
# Using yay
yay -S cursor-ai-bin

# Using paru
paru -S cursor-ai-bin

# Using makepkg (manual)
git clone https://aur.archlinux.org/cursor-ai-bin.git
cd cursor-ai-bin
makepkg -si
```

After install/update, pacman prints a short package message with the AUR page URL for support and issue reporting.

## Repository layout

| File | Purpose |
|------|---------|
| `.github/workflows/update-aur.yml` | Scheduled update + publish workflow |
| `PKGBUILD.sed` | Template used by the workflow |
| `PKGBUILD` | Current generated package recipe |
| `test_bash_workflow.sh` | Local dry-run generator/validator |
| `local_update.sh` | Interactive local updater/installer |
| `TESTING.md` | Testing guide and checklist |

## Automated workflow

1. Read current package version/commit from `PKGBUILD`.
2. Query AUR metadata and Cursor update API.
3. Download latest `.deb` and compute SHA512.
4. Regenerate `PKGBUILD` from `PKGBUILD.sed`.
5. Validate generated fields.
6. Commit to the repo branch.
7. Optionally publish to AUR only when manually requested.

By default, scheduled and manual runs update this repository only and do not touch AUR credentials or publish to AUR.
When triggered manually, `workflow_dispatch` supports `publish_to_aur=true` to publish to AUR from a publishable branch.
It also supports `force_publish=true` to regenerate/commit even if versions already match.

## Branch behavior

- `dev`: update + validation only, no AUR publish.
- `main`: update + optional AUR publish when `publish_to_aur=true`.

## Local testing

```bash
./test_bash_workflow.sh
```

To generate from Cursor's `latest` release track instead of the default stable/golden flow:

```bash
./test_bash_workflow.sh --latest
mv PKGBUILD.test PKGBUILD
makepkg --printsrcinfo > .SRCINFO
makepkg -Csfci
```

The `latest` API may omit `debUrl`, so the local script derives the `.deb` URL from the returned `version` and `commitSha`.

Optional checks:

```bash
makepkg --verifysource --noconfirm
makepkg -s
```

## Local update helper

For an interactive local update on your own machine:

```bash
./local_update.sh
```

The helper fetches the newest Cursor release metadata, generates and validates
`PKGBUILD.test`, optionally shows the generated recipe and diff, asks before
replacing `PKGBUILD`, asks before checking sources with `makepkg --verifysource`,
asks before running `makepkg -si`, and asks before deleting local build artifacts
such as `pkg/`, `src/`, downloaded `.deb` files, and built package archives.

## Why bundled runtime

Cursor staff has confirmed that community AUR packages can break if they run against a different system Electron version than Cursor's tested runtime for that release. This package keeps the runtime bundled from Cursor's official `.deb` build to avoid those mismatches.

## Troubleshooting T3 Code launch behavior

If Cursor opens fine from your terminal but T3 Code hangs or fails to launch it, the issue is usually the CLI entrypoint, not the Electron runtime itself.

- T3 Code launches editors through CLI commands and expects non-blocking launcher behavior.
- `cursor-ai-bin` now installs `/usr/bin/cursor` as a launcher wrapper that forwards to Cursor's upstream launcher and loads `~/.config/cursor-flags.conf`.
- If `cursor` points directly to the raw app binary instead of the launcher path, behavior can differ (TTY attachment, ignored flags, or editor integration issues).

Quick checks:

```bash
command -v cursor
readlink -f "$(command -v cursor)"
file "$(command -v cursor)"
```

Expected:

- `command -v cursor` resolves to `/usr/bin/cursor`
- `file ...` reports a shell script launcher (not only an ELF binary target)

Validate flags file format:

```bash
mkdir -p ~/.config
printf '%s\n' '--ozone-platform=wayland' > ~/.config/cursor-flags.conf
```

Update/reinstall package after launcher changes:

```bash
yay -Syu cursor-ai-bin
# or
paru -Syu cursor-ai-bin
```

If T3 Code still fails:

- Ensure `cursor` is available in the same `PATH` seen by T3 Code.
- Set editor selection to Cursor again inside T3 Code so it re-resolves the command.
- Test with explicit command path `/usr/bin/cursor`.

## Contributing

1. Fork the repository.
2. Create a branch from `dev`.
3. Run `./test_bash_workflow.sh`.
4. Open a PR against `dev`.

## Links

- [Cursor official site](https://www.cursor.com)
- [AUR cursor-ai-bin package](https://aur.archlinux.org/packages/cursor-ai-bin)
- [Arch Linux AUR guidelines](https://wiki.archlinux.org/title/AUR_submission_guidelines)
