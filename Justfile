set shell := ["bash", "-uc"]

plugin_link := env("HOME") / ".config/omarchy/plugins/lbssousa.fingerprint"

default:
    @just --list

# Every test: the overlay's JS model and catalogs, the D-Bus helper, QML lint.
test: test-js test-py lint

test-js:
    node --test tests/js/

# The helper's protocol against a fake bus (no fprintd needed).
test-py:
    python3 -I -m unittest discover -s tests/py

# qmllint over the plugin (warnings only: the shell's qs.* modules aren't
# importable outside it) and shellcheck when installed.
lint:
    #!/usr/bin/env bash
    set -uo pipefail
    if command -v shellcheck >/dev/null; then shellcheck bin/*; fi
    /usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml plugin/*.qml || true

# Run the overlay in a separate Quickshell instance (dev/), against the real
# reader; Escape ends it. `just dev ar` shows it in another language than the shell's.
dev language="":
    #!/usr/bin/env bash
    set -eu
    if [ -n "{{language}}" ]; then
      export OMARCHY_LANGUAGE_FILE=$(mktemp)
      trap 'rm -f "$OMARCHY_LANGUAGE_FILE"' EXIT
      echo "{{language}}" > "$OMARCHY_LANGUAGE_FILE"
    fi
    quickshell -p dev

# Load this checkout's plugin in the real shell, then open it.
link:
    ln -sfn "$PWD/plugin" {{plugin_link}}
    omarchy-shell shell enablePlugin lbssousa.fingerprint '{}'
    omarchy-restart-shell

# Build the Arch package into packaging/.
pkg:
    cd packaging && makepkg -f
