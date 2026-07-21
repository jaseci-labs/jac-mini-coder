#!/bin/bash
# jac-mini-coder installer — everything you need to write Jac with a local model.
#
#   curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac-mini-coder/main/install.sh | bash
#
# What it does (idempotent — safe to re-run):
#   1. native `jac` binary            (jaseci install script)  → ~/.local/bin/jac
#   2. ollama                         (linux: official script · macOS: brew)
#   3. the model                      (default gemma4:e4b, ~10 GB — JAC_MINI_MODEL overrides)
#   4. jac-mini-coder source          → ~/.jac-mini-coder     (JAC_MINI_HOME overrides)
#   5. project deps (`jac install`) + a `jac-mini-coder` launcher on ~/.local/bin
#
# Then just run:  jac-mini-coder
set -euo pipefail

MODEL="${JAC_MINI_MODEL:-gemma4:e4b}"
DIR="${JAC_MINI_HOME:-$HOME/.jac-mini-coder}"
REPO="jaseci-labs/jac-mini-coder"
BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"

say()  { printf '\033[1m⚒ %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

OS="$(uname -s)"

say "jac binary"
if command -v jac >/dev/null 2>&1; then
  jac --version | head -1
else
  curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
  command -v jac >/dev/null 2>&1 || die "jac install failed — see https://www.jac-lang.org"
  jac --version | head -1
fi

say "ollama"
if ! command -v ollama >/dev/null 2>&1; then
  case "$OS" in
    Linux)  curl -fsSL https://ollama.com/install.sh | sh ;;
    Darwin) if command -v brew >/dev/null 2>&1; then brew install ollama
            else die "install ollama first: https://ollama.com/download (or install homebrew)"; fi ;;
    *)      die "unsupported OS: $OS — install ollama manually: https://ollama.com/download" ;;
  esac
fi
# make sure the daemon answers (linux installer starts a service; elsewhere, start one)
if ! ollama list >/dev/null 2>&1; then
  say "starting ollama daemon"
  (nohup ollama serve >/dev/null 2>&1 &) ; sleep 3
  ollama list >/dev/null 2>&1 || die "ollama daemon did not come up — start it manually: ollama serve"
fi
echo "ollama ready"

say "model: $MODEL"
if ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "already pulled"
else
  ollama pull "$MODEL"
fi

say "jac-mini-coder source → $DIR"
if [ -d "$DIR/.git" ] && command -v git >/dev/null 2>&1; then
  git -C "$DIR" pull --ff-only 2>/dev/null || true
elif [ ! -f "$DIR/main.jac" ]; then
  ok=""
  if command -v git >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "https://github.com/$REPO.git" "$DIR" 2>/dev/null && ok=1
  fi
  if [ -z "$ok" ]; then
    # prefer the latest release tarball; fall back to main
    TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
           | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    mkdir -p "$DIR"
    if [ -n "$TAG" ]; then
      curl -fsSL "https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz" 2>/dev/null \
        | tar xz -C "$DIR" --strip-components=1 2>/dev/null && ok=1 || true
    fi
    if [ -z "$ok" ]; then
      curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" 2>/dev/null \
        | tar xz -C "$DIR" --strip-components=1 2>/dev/null && ok=1 || true
    fi
  fi
  if [ -z "$ok" ] && [ -f "./main.jac" ] && [ -f "./minicoder.jac" ]; then
    # running from inside a checkout (pre-release / private repo)
    cp -R ./. "$DIR"/ && ok=1
  fi
  [ -n "$ok" ] && [ -f "$DIR/main.jac" ] || die "could not fetch $REPO (not public yet?) — clone it manually to $DIR"
fi

say "project dependencies"
( cd "$DIR" && jac install ) || true   # deps may already be satisfied by the runtime closure
( cd "$DIR" && jac check main.jac >/dev/null 2>&1 ) || die "sanity check failed in $DIR"

say "launcher"
mkdir -p "$BIN"
cat > "$BIN/jac-mini-coder" <<LAUNCH
#!/bin/sh
# jac-mini-coder launcher — workspace defaults to ./jac-mini-work under your CWD
WS="\${1:-\$PWD/jac-mini-work}"
export PATH="\$HOME/.local/bin:\$PATH"
cd "$DIR" && exec jac run main.jac -- "\$WS"
LAUNCH
chmod +x "$BIN/jac-mini-coder"
echo "installed: $BIN/jac-mini-coder"

say "done"
echo
echo "  run:            jac-mini-coder"
echo "  pick workspace: jac-mini-coder ./myproject"
echo "  other models:   JAC_MINI_MODEL=qwen3:8b (re-run installer) or /model in the TUI"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  NOTE: add ~/.local/bin to your PATH";; esac
