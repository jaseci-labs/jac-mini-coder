<p align="center">
  <img src="assets/mascot.svg" width="120" alt="jac-mini-coder ninja mascot">
</p>

<h1 align="center">jac-mini-coder ⚒</h1>

<p align="center">
  <b>A Jac coding agent small enough for small models.</b><br>
  Build, serve, and verify Jac apps with a model running on your own machine.
</p>

<p align="center">
  <a href="https://github.com/jaseci-labs/jac-mini-coder/releases"><img src="https://img.shields.io/github/downloads/jaseci-labs/jac-mini-coder/total?color=f26b21&label=downloads" alt="downloads"></a>
  <a href="https://github.com/jaseci-labs/jac-mini-coder/releases/latest"><img src="https://img.shields.io/github/v/release/jaseci-labs/jac-mini-coder?color=f26b21&label=release" alt="latest release"></a>
  <a href="https://www.jac-lang.org"><img src="https://img.shields.io/badge/built%20with-Jac-f26b21" alt="built with Jac"></a>
</p>

---

jac-mini-coder writes Jac for you — backends, fullstack web apps, multi-user apps
with accounts, and apps with their own built-in AI assistant — and it **builds,
serves, and verifies** each one before saying it's done. It runs on a **~4B model
on your own laptop or GPU**: no cloud required, no API key required, nothing
leaves your machine.

```
⚒ > Build a tiny notes API: create_note(title, body) and list_notes endpoints.
⏺ route → build_backend
⏺ plan · declare · implement
  ⎿ ✓ build gate
  ⎿ ✓ runtime gate     ← served live: create a note, then list it back
  ⎿ ✓ done
⏺ OK  backend built and verified
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac-mini-coder/main/install.sh | bash
jac-mini-coder
```

That sets up everything it needs — the [`jac`](https://www.jac-lang.org) runtime,
[ollama](https://ollama.com), and the default `gemma4:e4b` model — and adds a
`jac-mini-coder` command to your PATH. Re-run any time; update in place with
`/update` inside the app.

Then just type what you want built.

## What you can build

With the model running locally on **gemma4:e4b (~4B, ~10 GB)** — a single
consumer GPU or an Apple-silicon laptop:

| Ask for… | You get |
|---|---|
| **a backend / API** | a served graph API with real endpoints, verified live |
| **a web app** | the backend **+** a styled UI, click-tested in a real browser |
| **accounts & sharing** | login, private data, shared team boards, admin-only actions |
| **an AI assistant in the app** | an app whose assistant answers questions about *your* data |
| **"add an endpoint to …"** | it extends your existing project and re-checks everything |
| **"fix the bug where …"** | it reproduces the bug first, then fixes it |

If a request genuinely can't be done, it tells you honestly instead of shipping
something broken.

> **Try it:** *"Build a recipe box web app with an AI assistant: add_recipe(name,
> steps) and list_recipes, plus the assistant answers questions about my saved
> recipes. Nice UI."*

## Choose your model

**On first launch it asks you to choose** — and you can change it any time with
`/model`:

1. **Local (ollama)** — free, private, offline. Pick from your installed models
   or type any name. Default `gemma4:e4b`; smaller `gemma4:e2b` and others like
   `qwen3:8b` work too. **This is the recommended path.**
2. **Z.ai GLM Coding Plan** — use your flat-monthly subscription key and pick a
   GLM model (`glm-4.7` / `glm-5.1` / …).
3. **Other API** — any hosted model, via a
   [litellm](https://docs.litellm.ai/docs/providers) provider spec + your key
   (OpenAI, Anthropic, Gemini, Groq, OpenRouter, or a custom endpoint).

Your choice is saved to `~/.jac-mini-coder/config.json`. When you build an app
*with AI in it*, that app uses the same model you picked — your key is used at
run time and never written into the generated app.

**Switching from inside the app:**

| command | does |
|---|---|
| `/model` | open the model chooser |
| `/model ollama_chat/qwen3:8b` | switch to a local model directly |
| `/api zai-code` | Z.ai Coding Plan (asks for your plan key) |
| `/api <provider/model> [key]` | any other hosted model |

Your API key is only stored if you paste one — if the provider's key is already
in your environment, the app uses that and writes nothing to disk.

## Commands

```
/model              choose or switch model
/dir <path>         change workspace
/update             upgrade to the latest version
/help · /quit
anything else       a task — it figures out build vs. edit vs. fix
```

## Running on a GPU server

`./box_init.sh ubuntu@HOST` sets up a fresh machine end to end — the runtime,
ollama, the model, and a smoke test — so you can point jac-mini-coder at a remote
box. See the script header for the couple of env vars it prints when it's done.

---

<sub>Built with [Jac](https://www.jac-lang.org). The agent works by walking a fixed
task-graph and filling a few typed, scoped slots — the harness does the
scaffolding, templating, and live verification, so a small model is enough.</sub>
