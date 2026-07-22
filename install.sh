#!/bin/bash
# jac-mini-coder installer — everything you need to write Jac with your own model.
#
#   curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac-mini-coder/main/install.sh | bash
#
# What it does (idempotent — safe to re-run):
#   1. native `jac` binary            (jaseci install script)  → ~/.local/bin/jac
#   2. asks: local ollama, or a hosted API (Z.ai coding plan / any litellm spec)
#   3. LOCAL only: ollama + the model  (default gemma4:e4b, ~10 GB)
#   4. jac-mini-coder source          → ~/.jac-mini-coder     (JAC_MINI_HOME overrides)
#   5. project deps (`jac install`) + a `jac-mini-coder` launcher on ~/.local/bin
#   6. saves your model choice         → ~/.jac-mini-coder/config.json (chmod 600)
#
# Non-interactive (piped with no terminal, CI): defaults to local ollama + gemma4:e4b.
# Override the local model with JAC_MINI_MODEL=<name>.
#
# Then just run:  jac-mini-coder
set -euo pipefail

MODEL="${JAC_MINI_MODEL:-gemma4:e4b}"
DIR="${JAC_MINI_HOME:-$HOME/.jac-mini-coder}"
CONF="$HOME/.jac-mini-coder/config.json"
REPO="jaseci-labs/jac-mini-coder"
BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"

say()  { printf '\033[1m⚒ %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
# read from the terminal even when the script is piped from curl | bash
ask()  { local a=""; if [ -r /dev/tty ]; then read -r -p "$1" a </dev/tty || true; fi; printf '%s' "$a"; }
asks() { local a=""; if [ -r /dev/tty ]; then read -r -s -p "$1" a </dev/tty || true; echo >/dev/tty; fi; printf '%s' "$a"; }

OS="$(uname -s)"

say "jac binary"
# minimum jac the current jac-mini-coder sources are known to check clean on.
# An older jac already on PATH is upgraded (skipping this was the #1 fresh-machine
# 'sanity check failed' cause — code written for a newer jac hits old syntax).
MIN_JAC="0.34.0"
ver_ok() {  # ver_ok CUR MIN  → 0 if CUR >= MIN
  [ -n "$1" ] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}
CUR_JAC=""
command -v jac >/dev/null 2>&1 && CUR_JAC="$(jac --version 2>/dev/null | sed -n 's/^jac \([0-9][0-9.]*\).*/\1/p')"
if ver_ok "$CUR_JAC" "$MIN_JAC"; then
  echo "jac $CUR_JAC"
else
  [ -n "$CUR_JAC" ] && echo "jac $CUR_JAC is older than $MIN_JAC — upgrading"
  curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
  command -v jac >/dev/null 2>&1 || die "jac install failed — see https://www.jac-lang.org"
  NEW_JAC="$(jac --version 2>/dev/null | sed -n 's/^jac \([0-9][0-9.]*\).*/\1/p')"
  jac --version | head -1
  ver_ok "$NEW_JAC" "$MIN_JAC" || echo "  ⚠ jac $NEW_JAC is still below $MIN_JAC — the install may fail its sanity check"
fi

# ── choose model / provider ──────────────────────────────────────────────────
# Defaults (local ollama) are used when there is no terminal to prompt on.
MODE="local"; C_MODEL="ollama_chat/$MODEL"; C_KEY=""; C_BASE=""; C_MF="false"
if [ -r /dev/tty ]; then
  say "choose your model"
  printf '  \033[1m1)\033[0m Local ollama   — free, private; the harness is tuned for gemma4  [default]\n'
  printf '  \033[1m2)\033[0m Z.ai Coding Plan — subscription key; glm-4.7 / glm-5.1 / …\n'
  printf '  \033[1m3)\033[0m Other hosted API — any litellm provider/model + key\n'
  CH="$(ask '  1/2/3 [1] > ')"; CH="${CH:-1}"
  case "$CH" in
    2) MODE="hosted"
       GLM="$(ask '  GLM model [glm-4.7] > ')"; GLM="${GLM:-glm-4.7}"
       C_KEY="$(asks '  Z.ai plan API key (hidden) > ')"
       C_MODEL="openai/$GLM"; C_BASE="https://api.z.ai/api/coding/paas/v4"; C_MF="true"
       [ -n "$C_KEY" ] || die "no key entered — re-run and paste your Z.ai plan key" ;;
    3) MODE="hosted"
       printf '  litellm spec examples: openai/gpt-5.2-mini · anthropic/claude-haiku-4-5 · gemini/gemini-2.5-flash · groq/… · zai/glm-4.7\n'
       SP="$(ask '  litellm spec (provider/model) > ')"
       [ -n "$SP" ] || die "no spec entered"
       case "$SP" in */*) ;; *) die "spec needs a provider prefix, e.g. openai/gpt-5.2-mini";; esac
       C_KEY="$(asks '  API key (hidden; blank if already in your env) > ')"
       BU="$(ask '  base URL override [blank = provider default] > ')"
       C_MODEL="$SP"; C_BASE="$BU"; C_MF="true" ;;
    *) MODE="local"
       # the two models the template-first harness is calibrated on. Skip the
       # sub-prompt if JAC_MINI_MODEL was set explicitly.
       if [ -z "${JAC_MINI_MODEL:-}" ]; then
         printf '  \033[1ma)\033[0m gemma4:e4b (~4B, ~10 GB) — stronger, recommended  [default]\n'
         printf '  \033[1mb)\033[0m gemma4:e2b (~2B, ~7 GB)  — lighter, for smaller GPUs / laptops\n'
         LM="$(ask '  a/b or any ollama model name [a] > ')"; LM="${LM:-a}"
         case "$LM" in
           a|A) MODEL="gemma4:e4b" ;;
           b|B) MODEL="gemma4:e2b" ;;
           *)   MODEL="$LM" ;;
         esac
         C_MODEL="ollama_chat/$MODEL"
       fi ;;
  esac
fi

if [ "$MODE" = "local" ]; then
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
else
  say "hosted model: $C_MODEL"
  echo "skipping ollama + local model download — your model runs in the cloud"
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
if ! CK="$( cd "$DIR" && jac check main.jac 2>&1 )"; then
  printf '\033[31m%s\033[0m\n' "$CK" | tail -25 >&2
  echo >&2
  printf 'jac version: %s\n' "$(jac --version 2>&1 | head -1)" >&2
  die "sanity check failed in $DIR (errors above). This is usually a jac version mismatch — please share the errors + 'jac --version' at https://github.com/$REPO/issues"
fi

# ── save the model choice so the TUI starts ready (no first-run prompt) ───────
say "saving model choice → $CONF"
mkdir -p "$HOME/.jac-mini-coder"
# JSON-escape the two free-text fields (key, base URL) just in case
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
cat > "$CONF" <<JSON
{
 "model": "$(esc "$C_MODEL")",
 "api_key": "$(esc "$C_KEY")",
 "http_base": "",
 "api_base": "$(esc "$C_BASE")",
 "model_first": $C_MF
}
JSON
chmod 600 "$CONF"
[ "$MODE" = "hosted" ] && echo "model-first (autonomy) on — capable models write each block; templates are the fallback"

say "launcher"
mkdir -p "$BIN"
cat > "$BIN/jac-mini-coder" <<LAUNCH
#!/bin/sh
# jac-mini-coder launcher — workspace defaults to ./jac-mini-work under your CWD
#
# Two things this has to get right, because it cd's into the install dir before
# running: a bare "--" separator must not become the workspace name, and a
# relative path must resolve against YOUR shell's directory, not the engine's.
# Both were wrong, so \`jac-mini-coder -- ~/work\` landed in ~/.jac-mini-coder/--
# and the advertised \`jac-mini-coder ./myproject\` landed inside the install dir.
[ "\$1" = "--" ] && shift
WS="\${1:-\$PWD/jac-mini-work}"
case "\$WS" in
  "~") WS="\$HOME" ;;
  "~/"*) WS="\$HOME/\${WS#"~/"}" ;;
  /*) ;;
  *) WS="\$PWD/\$WS" ;;
esac
export PATH="\$HOME/.local/bin:\$PATH"
export JACMINI_CWD="\$PWD"
mkdir -p "\$WS" 2>/dev/null
cd "$DIR" && exec jac run main.jac -- "\$WS"
LAUNCH
chmod +x "$BIN/jac-mini-coder"
echo "installed: $BIN/jac-mini-coder"

say "done"
echo
echo "  run:            jac-mini-coder"
echo "  pick workspace: jac-mini-coder ./myproject"
echo "  change model:   /model in the TUI  ·  autonomy: /autonomy"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  NOTE: add ~/.local/bin to your PATH";; esac
