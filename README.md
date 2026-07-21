# ⚒ jac-mini-coder

**A Jac coding agent small enough for small models.** It writes, builds, serves,
and *verifies* Jac — backends, fullstack web apps, auth/multi-user apps, and
agentic (AI-in-the-app) apps — driven by a **~4B model running on your own
machine**. No cloud required, no API key required.

Most coding agents are an open ReAct loop: a big hosted model, a big tool menu,
and a prompt full of instructions the model is trusted to follow. A small local
model gets lost in that loop — so "local coding agent" usually means "worse
coding agent."

jac-mini-coder inverts the design: **the procedure is the program.** Each task
class is a compiled task-graph — mandatory stations the run *must* visit — and
the model's role shrinks to a handful of typed, scoped slots. Everything else is
code: scaffolding, stub synthesis, standard-block templates, file assembly, live
verification, and most repairs. The harness carries the discipline, so the model
doesn't have to.

```
⚒ > Build a tiny notes API: create_note(title, body) and list_notes endpoints.
⏺ route → build_backend
⏺ plan_build (plan)
⏺ author_decls (declare)     ⎿ ✓ passed
⏺ template  impl create_note.run · list_notes.run · list_notes.collect
  ⎿ ✓ build gate
  ⎿ ✓ runtime gate     ← served live: register → create → list must return the data
  ⎿ ✓ done
⏺ OK  backend built and verified
```

## What a local gemma can actually build

The whole point: with the harness doing the coordination, **gemma4:e4b (~4B,
~10 GB) on a single consumer GPU or an Apple-silicon laptop** clears every route
— no fine-tuning, no frontier model.

| Route | What it produces | gemma4:e4b |
|---|---|---|
| **backend** | a served graph API — nodes, walkers, endpoints | ✓ ~20 s, verified live |
| **fullstack** | backend **+** a styled web UI, click-tested in a real browser | ✓ |
| **multi-user** | accounts, private/shared/admin data, two-user isolation checks | ✓ |
| **agentic** | an app with its own `by llm()` assistant grounded in your graph | ✓ |
| **add_endpoint** | extends a live project, regression-checks every endpoint | ✓ |
| **fix_bug** | reproduces via the gate ladder *before* changing anything | ✓ |

Even **gemma4:e2b (~2B)** clears every route — the harness holds the line where
the model is weakest. And when a run genuinely can't be done, the gates say so
honestly instead of shipping something broken.

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac-mini-coder/main/install.sh | bash
jac-mini-coder
```

The installer sets up whatever's missing — the native
[`jac`](https://www.jac-lang.org) binary, [ollama](https://ollama.com), and the
default model (`gemma4:e4b`) — and puts a `jac-mini-coder` launcher on your PATH.
Idempotent; re-run any time. Update in place with `/update` inside the TUI.

Manual alternative:

```bash
ollama pull gemma4:e4b
git clone https://github.com/jaseci-labs/jac-mini-coder.git && cd jac-mini-coder
jac install
jac run main.jac
```

Then just type what you want built. Headless (scripts/CI):
`jac run cli.jac -- "<task>" <workspace>`.

## Choosing your model

**On first launch the TUI asks you to choose** — and you can change it any time
with `/model`. Three options:

1. **Local (ollama)** — free, private, offline. Pick from your installed models
   (listed for you) or type any name. Default `gemma4:e4b`; `gemma4:e2b` and
   `qwen3:8b` also work. This is the recommended path — it's what the harness is
   designed around.
2. **Z.ai GLM Coding Plan** — a flat-monthly subscription, *not* pay-per-token.
   Enter your plan key and pick a GLM model (`glm-4.7` / `glm-5.1` / …); it's
   routed through the plan's OpenAI-compatible
   [coding endpoint](https://docs.z.ai/devpack/tool/others).
3. **Other API** — any hosted model [litellm](https://docs.litellm.ai/docs/providers)
   supports: a provider-prefixed spec + your key, with an optional base-URL
   override for gateways or self-hosted OpenAI-compatible servers (vLLM,
   LM Studio, llama.cpp).

Your choice persists in `~/.jac-mini-coder/config.json` (chmod 600).

### Switching model from the TUI

| command | what it does |
|---|---|
| `/model` or `/config` | open the config screen (local / Z.ai / other API) |
| `/model ollama_chat/qwen3:8b` | switch to a local model directly |
| `/api zai-code` | Z.ai Coding Plan — prompts for your plan key |
| `/api <provider/model> [key] [base-url]` | any litellm spec; base-URL is optional |

**Where your API key is stored.** For a hosted spec, jac-mini-coder asks litellm
which environment variable that provider uses (`ANTHROPIC_API_KEY`,
`GEMINI_API_KEY`, `ZAI_API_KEY`, …). If it's already exported, blank input uses
it and **nothing is written to disk**; otherwise a pasted key is saved to
`config.json` (chmod 600).

Environment variables override the saved config: `JACMINI_MODEL`,
`JACMINI_API_KEY`, `JACMINI_API_BASE`, `JACMINI_HTTP_BASE`.

### Agentic apps inherit your choice

Ask for an app with AI in it — *"a recipe box with an assistant that answers
questions about my saved recipes"* — and the generated app gets its own typed
`by llm()` slot, grounded in the user's graph data, wired to the **same model you
picked**. The key is read at serve time (`JAC_AI_*` env → your config → local
ollama), never baked into the generated source.

## TUI commands

```
/model · /config     model config screen (local ollama / Z.ai plan / other API)
/model <spec>         switch a local model directly (ollama_chat/<name>)
/api <spec|preset> [key] [base-url]   hosted model via litellm
/http <base>          byllm http_client mode via the adapter (small-model boxes)
/dir <path>           switch workspace
/update               upgrade to the latest release
/help · /quit
anything else         a task — the router picks build / add_endpoint / fix_bug
```

## How it works

```
task ─→ route (code) ─→ ┌ build_backend    plan → scaffold → declare → implement → verify
                        ├ build_fullstack  … + code-derived UI → browser + vision gates
                        ├ add_endpoint     plan-add → declare-add → implement-add → verify-add
                        └ fix_bug          sense → reproduce (gates as red-check) → repair → verify
```

- **Typed slots, scoped context.** The model fills a typed plan, a declaration
  surface, and (rarely) an impl block — each call sees only its own slice plus a
  shape-specific micro-guide. No tool menu, no "what next."
- **Templates first.** Standard blocks (collectors, read-traversals, counts,
  create-with-fields, shared/admin writes) are **code-authored** from the plan
  and declarations. On standard CRUD the model writes *zero* implementation code.
- **A gate ladder that genuinely goes red.** Dialect lints → declaration
  completeness/shape → `jac check` → full build → **live serve** (register, call
  every endpoint with its example payload, require reads to surface what writes
  created) → for fullstack, a real headless-browser click-through and a
  multimodal vision judge of the rendered page.
- **Mechanical repair before model repair.** A missing walker is synthesized
  from its own endpoint spec, a missing node from the payload fields, junk text
  is scrubbed — the model only repairs what code cannot derive, and sees only the
  error lines that concern its block.

## Reliability

Same build task, N=5 runs of `gemma4:e4b`, as the harness absorbed one observed
failure class per revision — **no prompt tuning, no fine-tuning**:

| harness revision | result |
|---|---|
| open-loop baseline | 0/5 |
| + impl gates, live scenario assertion | 1/5 |
| + per-block fills, micro-compile acceptance | 1/5 |
| + templates, mechanical decl repair | **5/5, ~20 s/run** |

Generalizes across CRUD shapes (todo / bookmarks / inventory / contacts / events
all green), mutates live projects (`add_endpoint` regression-verifies every
existing endpoint), and `fix_bug` reproduces via the gate ladder before touching
anything — answering *"gates are green, could not reproduce"* rather than
inventing a fix.

## Gemma-family models: two required settings

`jac.toml` ships them; if you construct your own `Model`, keep both:

```toml
[plugins.byllm.model]
native_tools = true    # byLLM's gemma tool-call recovery otherwise eats any
                       # typed output containing a top-level "name" field
[plugins.byllm.call_params]
think = false          # gemma's thinking channel otherwise swallows content
```

## Running on a GPU server

`./box_init.sh ubuntu@HOST` provisions a fresh machine end-to-end: jac binary,
ollama (ctx 16384), the model, project files, and a smoke probe. On hosts where
the embedded runtime's litellm transport crashes (observed on glibc 2.39), it
auto-installs `byllm_adapter.py` as a systemd service — then run with
`JACMINI_MODEL=gemma4:e4b JACMINI_HTTP_BASE=http://127.0.0.1:11438`, or use
`/http http://127.0.0.1:11438` in the TUI.

## Layout

```
main.jac            the TUI (model config, live station/gate rendering)
cli.jac             headless runner (scripts, CI)
minicoder.jac       the engine: task-graphs, slots, templates, gates, repairs
fullstack.jac       the fullstack task-graph: UI renderers, browser + vision gates
mascot.jac          terminal pixel-art mascot
gen_pairs.jac       run traces → gate-labeled data pairs
byllm_adapter.py    http-mode adapter (for hosts that need it)
box_init.sh         one-command GPU server provisioning
```

Built with [Jac](https://www.jac-lang.org) — the graphs the agent walks are
object-spatial programs, and the typed slots are byLLM functions.
