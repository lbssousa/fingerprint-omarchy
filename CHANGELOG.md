# Changelog

## 0.1.0 (2026-10-27)

- First release: the `lbssousa.fingerprint` overlay (six finger tiles, test
  area, enrollment card with a square progress frame), `fprint-helper` over
  fprintd's D-Bus API, `omarchy-fingerprint`, catalogs for every Omarchy
  language.
- A scan survives fprintd restarting under it (resume, the goodix538d desync
  watchdog): the helper claims the reader again and starts over instead of
  waiting forever on a claim that died with the old fprintd.
