# Publishing notes

Maintainer notes for the Omarchy plugin marketplace.

- Category: Desktop
- Tags: workspaces, hyprland, quickshell
- Submission process: see `SUBMISSION.md` in https://github.com/omacom/omarchy-plugin-marketplace

## Release checklist

1. Bump `version` in `manifest.json` and add a `CHANGELOG.md` entry.
2. Run `/usr/share/omarchy/bin/omarchy-plugin-validate .` and the tests (`node tests/*.js`, `python3 -m unittest discover tests`).
3. Commit, tag (`git tag vX.Y.Z`), and push with tags.
4. Re-verify via the marketplace's verify flow.
