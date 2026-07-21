# ⚒ jac-mini-coder

**Write Jac with your own model.** Local ollama by default — no cloud, no
API keys. Or bring a hosted model via any litellm provider spec + your key.

Most coding agents are an open ReAct loop: a big hosted model, a big tool
menu, and a prompt full of instructions the model is trusted to follow. A
small local model gets lost in that loop — so "local coding agent" usually
means "worse coding agent."

jac-mini-coder inverts the design: **the procedure is the program**. Each task
class is a compiled task-graph — mandatory stations the run *must* visit — and
the model's role shrinks to a handful of typed, scoped slots. Everything else
is code: scaffolding, stub synthesis, standard-block templates, file assembly,
verification, and most repairs. The harness carries the discipline, so a ~4B
model running on your own machine via [ollama](https://ollama.com) produces
**served-and-verified Jac backends in ~20 seconds** — and when it can't, the
gates say so honestly instead of shipping something broken.

```
⚒ > Build a tiny notes API: create_note(title, body) and list_notes endpoints.
route → build_backend
  ⚒ plan_build plan
  ⚒ author_decls declare ✓
  ⚙ template  impl create_note.run with Root entry;
  ⚙ template  impl list_notes.run with Root entry;
  ⚙ template  impl list_notes.collect with Note entry;
  ✓ build gate
  ✓ runtime gate      ← served live: register → create → list must return the data
  ✓ done
OK backend built and verified
```

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jac-mini-coder/main/install.sh | bash
jac-mini-coder
```

The installer sets up everything that's missing — the native
[`jac`](https://www.jac-lang.org) binary, [ollama](https://ollama.com), and
the model (`gemma4:e4b`, ~10 GB; `JAC_MINI_MODEL=<name>` to choose another) —
and puts a `jac-mini-coder` launcher on your PATH. Idempotent; re-run any time.

Manual alternative:

```bash
ollama pull gemma4:e4b
git clone https://github.com/jaseci-labs/jac-mini-coder.git && cd jac-mini-coder
jac install
jac run main.jac
```

That's it — type what you want built. TUI commands: `/model <spec>` ·
`/api <spec> [key]` · `/dir <path>` · `/quit`; anything else is a task.
Headless: `jac run cli.jac -- "<task>" <workspace>`.

## Choose your model

On first run the TUI asks: local ollama, or a hosted API. The choice persists
in `~/.jac-mini-coder/config.json` (chmod 600).

- **Local** (default): any ollama model via `/model ollama_chat/<name>`.
  `gemma4:e4b` (~10 GB) runs on a single consumer GPU or Apple silicon.
- **Hosted**: `/api <provider/model> [key]` with a
  [litellm provider spec](https://docs.litellm.ai/docs/providers) — the
  provider prefix is required: `zai/glm-4.7`, `openai/gpt-5.2-mini`,
  `anthropic/claude-haiku-4-5`, `gemini/gemini-2.5-flash`, `groq/…`,
  `openrouter/…`. The key is prompted hidden if omitted.
- **Coding plan** (subscription APIs, not pay-per-token): `/api zai-code` routes
  GLM through the [Z.ai GLM Coding Plan](https://docs.z.ai/devpack/tool/others)'s
  OpenAI-compatible endpoint (`https://api.z.ai/api/coding/paas/v4`) using your
  plan key. Any other coding/gateway endpoint works via
  `/api <provider/model> <key> <base-url>` — the base URL overrides the
  provider default.
- Env vars override everything: `JACMINI_MODEL`, `JACMINI_API_KEY`,
  `JACMINI_API_BASE`, `JACMINI_HTTP_BASE`.

**Agentic apps inherit your choice.** Ask for an app with AI in it ("… with an
AI assistant that answers questions about my notes") and the generated app gets
its own typed `by llm()` slot, grounded in the user's graph data, wired to the
same model you picked — env first (`JAC_AI_MODEL` / `JAC_AI_API_KEY` /
`JAC_AI_HTTP_BASE`), then your saved config, then local ollama. Your API key is
read at serve time, never baked into the generated source.

## How it works

```
task ─→ route (code) ─→ ┌ build_backend   plan → scaffold → declare → implement → verify
                        ├ add_endpoint    plan-add → declare-add → implement-add → verify-add
                        └ fix_bug         sense → reproduce (gates as red-check) → repair → verify
```

- **Typed slots, scoped context.** The model fills a typed plan, a declaration
  surface, and (rarely) an impl block — each call sees only its own slice plus
  a shape-specific micro-guide. No tool menu, no "what next".
- **Templates first.** Standard blocks (collectors, read-traversals, counts,
  create-with-fields) are **code-authored** from the plan and declarations. On
  standard CRUD the model writes *zero* implementation code.
- **A gate ladder that genuinely goes red.** Dialect lints → declaration
  completeness/shape → `jac check` → full build → **live serve**: register,
  call every planned endpoint with its example payload, and require reads to
  surface what writes created.
- **Mechanical repair before model repair.** A missing walker is synthesized
  from its own endpoint spec, a missing node from the payload fields, junk
  text is scrubbed — the model only repairs what code cannot derive, seeing
  only the error lines that concern its block.

## Reliability

Same build task, N=5 runs of `gemma4:e4b`, as the harness absorbed one
observed failure class per revision (no prompt tuning, no fine-tuning):

| harness revision | result |
|---|---|
| open-loop baseline | 0/5 |
| + impl gates, live scenario assertion | 1/5 |
| + per-block fills, micro-compile acceptance | 1/5 |
| + templates, mechanical decl repair | **5/5, ~20 s/run** |

Generalizes across CRUD shapes (todo / bookmarks / inventory / contacts /
events APIs all green), mutates live projects (`add_endpoint`
regression-verifies every existing endpoint), and `fix_bug` reproduces via the
gate ladder before touching anything — answering "gates are green, could not
reproduce" rather than inventing a fix.

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
ollama (ctx 16384), the model, project files, and a smoke probe. On hosts
where the embedded runtime's litellm transport crashes (observed on glibc
2.39), it auto-installs `byllm_adapter.py` as a systemd service — then run
with `JACMINI_MODEL=gemma4:e4b JACMINI_HTTP_BASE=http://127.0.0.1:11438`, or use
`/http http://127.0.0.1:11438` in the TUI.

## Layout

```
main.jac            the TUI (live station/gate rendering)
cli.jac             headless runner (scripts, CI)
minicoder.jac        the engine: task-graphs, slots, templates, gates, repairs
gen_pairs.jac       run traces → gate-labeled data pairs
byllm_adapter.py    http-mode adapter (for hosts that need it)
box_init.sh         one-command GPU server provisioning
```

Built with [Jac](https://www.jac-lang.org) — the graphs the agent walks are
object-spatial programs, and the typed slots are byLLM functions.
