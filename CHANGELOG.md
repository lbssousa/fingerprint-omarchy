# Changelog

## Unreleased

- **Looks like Omarchy's own fingerprint panel** (`omarchy.fingerprint`,
  Omarchy 4.6): full screen, the big print on a dark scrim with one status
  line, arriving as a scratchy transmission and lighting up along its ridges
  with every scan accepted; after an enrollment it breaks up and comes back on
  the fingers. The cards, the square progress frame and the test area are
  gone: the six fingers sit under the print, and the print itself is the test.
  It keeps to what Omarchy's panel doesn't do: choosing the finger, testing,
  deleting.
- The lines the two panels share (touch, lift and touch again, the retry
  hints, the failures, "Fingerprint registered") are Omarchy's, with its
  translations; `dev/sync-upstream-strings` copies them from an installed
  Omarchy. The panel's own lines use Omarchy's word for it too: a finger is
  registered, not enrolled ("Registered", "Enter registers"), in English,
  Filipino, Hindi, Portuguese (Brazil), Slovenian, Urdu, Uzbek and Chinese;
  Tamil follows Omarchy's spacing.
- The PAM hint names Omarchy's `omarchy-setup-security-fingerprint` again;
  every catalog still named omarchy-multiuser's.
- `omarchy-fingerprint`, with the plugin off, runs Omarchy 4.6's setup
  directly (it opens its panel) instead of in a terminal.

## 0.3.0 (2026-11-12)

- The test names the recognized finger with several fingers enrolled, on an
  fprintd that emits `VerifyMatchedFinger` right before `verify-match`. Stock
  fprintd only names it when a single finger is enrolled, and the test then
  says just that a print was recognized, as before.

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
