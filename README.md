# ⚒ jac-mini-coder

**A Jac coding agent small enough for small models.**

Most coding agents are an open ReAct loop: a big model, a big tool menu, and a
prompt full of instructions the model is trusted to follow. A small local model
gets lost in that loop. jac-mini-coder inverts it: **the procedure is the
program**. Each task class is a compiled task-graph — mandatory stations the
agent *must* visit — and the model's role shrinks to a handful of typed,
scoped slots. Everything else is code: scaffolding, stub synthesis, file
assembly, verification, and most repairs.

The result: **gemma4:e4b (a ~4B local model) builds, extends, and fixes
served-and-verified Jac backends at parity with a frontier teacher** — ~20 s
per build, no fine-tuning, no cloud requirement for execution.

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

## How it works

```
task ─→ route (code) ─→ ┌ build_backend   plan → scaffold → declare → implement → verify
                        ├ add_endpoint    plan-add → declare-add → implement-add → verify-add
                        └ fix_bug         sense → reproduce (gates as red-check) → repair → verify
```

- **Typed slots, scoped context.** The model fills a typed `BuildPlan`, a
  decl surface, and (rarely) an impl block — each call sees only its own
  slice plus a shape-specific micro-guide. No tool menu, no "what next".
- **Templates first.** Standard blocks (collectors, read-traversals, counts,
  and the create block's field mapping) are **code-authored** from the plan
  and declarations. On standard CRUD the model authors *zero* impl blocks.
- **A gate ladder that genuinely goes red.** Lints (dialect drift, detached
  nodes, input clobbering) → decl completeness/shape → `jac check` →
  full build → **live serve**: register, call every planned endpoint with its
  example payload, and require reads to surface what writes created.
- **Mechanical repair before model repair.** A missing walker is synthesized
  from its own endpoint spec; a missing node from the payload fields; junk
  text is scrubbed. The model only repairs what code cannot derive — with
  only the error lines that concern its block.
- **Every run emits training data.** Slot inputs/outputs + gate verdicts
  stream to a JSONL trace; `gen_pairs.jac` turns traces into gate-labeled
  pairs (green = SFT gold, red→green = preference pairs).

## Quickstart

Requires the native [`jac`](https://www.jac-lang.org) binary and, for local
execution, [ollama](https://ollama.com).

```bash
git clone https://github.com/jaseci-labs/jac-mini-coder.git && cd jac-mini-coder
jac install

# with a frontier model (teacher):
export OPENAI_API_KEY=sk-...
jac run main.jac

# with a small local model (student):
ollama pull gemma4:e4b
SMITH_MODEL=ollama_chat/gemma4:e4b jac run main.jac
```

TUI commands: `/model <spec>` · `/http <base>` · `/dir <path>` · `/quit` —
anything else is a task. Headless: `jac run cli.jac -- "<task>" <workspace>`.

### Gemma-family models: two required settings

`jac.toml` ships them; if you build your own `Model`, keep both:

```toml
[plugins.byllm.model]
native_tools = true    # byLLM's gemma tool-call recovery otherwise eats any
                       # typed output containing a top-level "name" field
[plugins.byllm.call_params]
think = false          # gemma's thinking channel otherwise swallows content
```

### GPU box bring-up

`./box_init.sh ubuntu@HOST` provisions a fresh GPU machine end-to-end: jac
binary, ollama (ctx 16384), `gemma4:e4b`, project files, and a smoke probe.
On hosts where the embedded runtime's litellm transport crashes (observed on
glibc 2.39), it auto-installs `byllm_adapter.py` as a systemd service and
switches to http mode — then run with
`SMITH_MODEL=gemma4:e4b SMITH_HTTP_BASE=http://127.0.0.1:11438`.

## Does the structure actually carry the small model?

Same task, N=5 reliability sweeps of gemma4:e4b, as the harness absorbed one
observed failure class per round (no prompt tuning, no fine-tuning):

| harness revision | student result |
|---|---|
| open-loop baseline | 0/5 |
| + impl gates, scenario assertion | 1/5 |
| + per-block fills, micro-compile | 1/5 (first zero-repair green) |
| + templates, mechanical decl repair, scrub | **5/5 — teacher parity, ~20 s/run** |

Generalization: five different CRUD APIs (todo, bookmarks, inventory,
contacts, events) all green; `add_endpoint` mutates a live project and
regression-verifies every endpoint; `fix_bug` reproduces via the gate ladder,
repairs only implicated blocks, and answers honestly when gates can't
reproduce the report.

## Layout

```
main.jac            the TUI (rich REPL, live station/gate rendering)
cli.jac             headless runner (scripts, CI, sweeps)
jacsmith.jac        the engine: task-graphs, slots, templates, gates, repairs
gen_pairs.jac       traces → gate-labeled training pairs
byllm_adapter.py    http-mode adapter (small-model boxes)
box_init.sh         one-command GPU box provisioning
```

Built with [Jac](https://www.jac-lang.org) — the graphs the agent walks are
object-spatial programs, and the typed slots are byLLM functions.
