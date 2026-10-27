# Changelog

## 0.2.0 (2026-10-27)

- The plugin lives at the repository root, so `omarchy plugin add
  https://github.com/lbssousa/fingerprint-omarchy.git` installs it and it can
  be listed in the Omarchy plugin marketplace. `dev/` no longer carries
  symlinks: `just dev` builds its folder in a temporary directory.
- `manifest.json` gains license, homepage, repository and keywords; a
  `preview.png`; README sections on requirements, install, update and removal.
- `just validate` (part of `just test`) runs `omarchy plugin validate`.

## 0.1.1 (2026-10-27)

- Install notes, README, `just link` and the hint `omarchy-fingerprint` prints
  when the plugin is off now run `omarchy-shell shell rescanPlugins` before
  `enablePlugin`: a running shell doesn't see a newly linked plugin until it
  rescans, and `enablePlugin` answers `unknown` until then.

## 0.1.0 (2026-10-27)

- First release: the `lbssousa.fingerprint` overlay (six finger tiles, test
  area, enrollment card with a square progress frame), `fprint-helper` over
  fprintd's D-Bus API, `omarchy-fingerprint`, catalogs for every Omarchy
  language.
- A scan survives fprintd restarting under it (resume, the goodix538d desync
  watchdog): the helper claims the reader again and starts over instead of
  waiting forever on a claim that died with the old fprintd.
