"""jac-mini-coder — a Jac coding agent small enough for small models. ⚒

A standalone TUI over the minicoder compiled-task-graph engine. Local-first:
your ollama model fills a few typed slots; the harness — stations, templates,
gates, mechanical repairs — does everything else and verifies the result live.
Prefer a hosted model? Bring your own litellm spec + API key.

    jac run main.jac                 # interactive TUI (default workspace ./work)
    jac run main.jac -- ./mydir      # pick a workspace

Commands inside the TUI:
    /model · /config     model config screen — local ollama (installed models
                         listed), Z.ai Coding Plan (pick a GLM model), or any
                         custom litellm spec + key + base URL, with examples
    /model <spec>        switch local model directly (e.g. ollama_chat/qwen3:8b)
    /api <spec> [key] [base-url]
                         hosted model via litellm — provider-prefixed spec
                         (zai/glm-4.7 · openai/gpt-5.2-mini · anthropic/claude-haiku-4-5 ·
                          gemini/gemini-2.5-flash · groq/... · openrouter/...);
                         key prompted securely if omitted; base-url overrides the
                         provider endpoint (coding plans / gateways)
    /api zai-code [key]  Z.ai GLM Coding Plan (subscription) — routes glm-4.7
                         through the plan's OpenAI-compatible coding endpoint
    /http <base>         byllm http_client mode via the adapter (small-model boxes)
    /update              upgrade to the latest release (git pull in a clone;
                         otherwise re-runs the latest release installer)
    /dir <path>          switch workspace
    /quit                exit
    anything else        a task — build, add an endpoint, or fix a bug; the router decides

Model choice persists in ~/.jac-mini-coder/config.json (chmod 600). Env vars
JACMINI_MODEL / JACMINI_API_KEY / JACMINI_HTTP_BASE override the saved config.
Generated agentic apps (AI mode) follow the same choice at serve time.
"""

import os;
import sys;
import json;
import getpass;
import subprocess;
import traceback;
import minicoder;
import fullstack;
import mascot;
import byllm_patch;
import agent;
import from jaclang.byllm.lib { Model }
import from rich.console { Console }
import from rich.panel { Panel }
import from rich.text { Text }
import from rich { box as richbox }

glob console = Console();

glob CONF_PATH: str = os.path.join(os.path.expanduser("~"), ".jac-mini-coder", "config.json");

# coding-plan / gateway adapters: a litellm spec + a base-URL override.
# These are SUBSCRIPTION coding APIs (flat monthly), not the pay-per-token
# direct APIs — same key works across coding tools.
glob PRESETS: dict[str, dict[str, str]] = {
    "zai-code": {"spec": "openai/glm-4.7",
                 "base": "https://api.z.ai/api/coding/paas/v4",
                 "note": "Z.ai GLM Coding Plan (subscription; OpenAI-compatible endpoint)"}
};

# live spinner handle while a task runs (rich Status); events print above it
glob STATUS: any = None;

# plain-language names for what each slot/gate is actually doing — the progress
# sub-lines should read like narration, not like internal slot identifiers
glob SLOT_LABEL: dict[str, str] = {
    "plan_build": "planning it out", "plan_add": "planning the change",
    "author_decls": "designing the API surface", "repair_decls": "refining the declarations",
    "mech_repair": "auto-fixing the declarations", "author_decl_update": "extending the API surface",
    "fill_impl": "writing the logic", "template": "writing standard logic",
    "template_fallback": "using a safe template", "repair_impl": "fixing the logic",
    "style_copy": "choosing the look and wording", "judge_ui": "reviewing the design",
    "restyle_css": "restyling", "access_map": "mapping user permissions",
    "ai_mode": "adding the in-app assistant", "ai_endpoint_fold": "tidying the AI endpoint",
    "sense": "reading the project", "repair_decls_error": "declaration repair failed"
};
glob GATE_LABEL: dict[str, str] = {
    "build": "compiling", "runtime": "serving and testing it live",
    "ui": "clicking through the UI", "check": "type-checking"
};

glob STATION_VERB: dict[str, str] = {
    "plan": "Planning", "scaffold": "Scaffolding", "declare": "Declaring",
    "implement": "Forging", "verify": "Verifying", "done": "Polishing",
    "sense": "Sensing", "reproduce": "Reproducing", "repair": "Repairing"
};


def load_conf -> dict[str, str] {
    try {
        with open(CONF_PATH) as f { return json.load(f); }
    } except Exception { return {}; }
}

def save_conf(conf: dict[str, str]) {
    try {
        os.makedirs(os.path.dirname(CONF_PATH), exist_ok=True);
        data: dict[str, any] = dict(conf);
        # the model-first (autonomy) preference travels with the config
        data["model_first"] = minicoder.MODEL_FIRST;
        with open(CONF_PATH, "w") as f { json.dump(data, f, indent=1); }
        os.chmod(CONF_PATH, 384);  # 0o600 — the file may hold an API key
    } except Exception {}
}

"""Re-write the config with the current autonomy state (read-modify-write so
model/key/base are preserved). Keeps a /autonomy toggle or the non-gemma prompt
sticky across sessions."""
def persist_model_first(on: bool) {
    minicoder.MODEL_FIRST = on;
    c = load_conf();
    keep: dict[str, str] = {};
    for k in ["model", "api_key", "http_base", "api_base"] { keep[k] = str(c.get(k, "")); }
    save_conf(keep);
}


"""Pick a meaningful line out of a gate's error dump — `jac check` leads with
'Checking <file>...' headers and progress noise that say nothing to the user."""
def _first_err(errs: str) -> str {
    for ln in errs.split("\n") {
        t = ln.strip();
        if not t { continue; }
        if t.startswith("✖ Error:") { t = t.split("✖ Error:", 1)[1].strip(); }
        if t.startswith("Checking") or t.startswith("✔") or (not t) { continue; }
        if t.endswith("...") or t.startswith("=") or t.startswith("-") { continue; }
        if ("error[" in t) or ("COMPLETENESS" in t) or ("IMPL-" in t) or ("MULTI-USER" in t)
            or ("UI:" in t) or ("RUNTIME" in t) or ("Cannot" in t) or ("Expected" in t) {
            return t[:80];
        }
    }
    return "";
}

"""Build progress as dim sub-lines threaded under the current agent turn."""
def render_event(rec: dict) {
    kind = str(rec.get("kind", ""));
    station = str(rec.get("station", ""));
    if STATUS is not None {
        verb = STATION_VERB.get(station, "Working");
        try { STATUS.update("[orange3]✳[/orange3] [bold]" + verb + "…[/bold] [dim](ctrl+c to interrupt)[/dim]"); }
        except Exception {}
    }
    if kind == "slot" {
        slot = str(rec.get("slot", ""));
        if slot == "template" {
            console.print("  [dim]│ writing standard logic[/dim]");
        } elif slot == "mech_repair" {
            console.print("  [dim]│ auto-fixing the declarations[/dim]");
        } else {
            ok = rec.get("gate_ok", None);
            mark = "";
            if ok is not None { mark = " [green]✓[/green]" if ok else " [red]✗[/red]"; }
            label = SLOT_LABEL.get(slot, slot);
            console.print(f"  [dim]│ {label}[/dim]{mark}");
            if (ok is not None) and (not ok) {
                err = _first_err(str(rec.get("gate_errors", "")));
                if err { console.print(f"  [dim]│   {err}[/dim]"); }
            }
        }
    } elif kind == "gate" {
        gate = str(rec.get("gate", ""));
        glabel = GATE_LABEL.get(gate, gate);
        if rec.get("gate_ok", False) {
            console.print(f"  [dim]│[/dim] [green]✓[/green] [dim]{glabel}[/dim]");
        } else {
            err = _first_err(str(rec.get("gate_errors", "")));
            console.print(f"  [dim]│[/dim] [red]✗ {glabel}[/red] [dim]{err}[/dim]");
        }
    } elif kind == "run" {
        console.print("  [dim]│[/dim] [green]✓ done[/green]");
    }
}


"""Bind the chosen model into both engine modules. Three modes:
http adapter (small-model boxes) > hosted API (litellm spec + key) > local ollama.
A config-supplied api_base (coding plans / gateways) reaches litellm via the
byllm_patch applied at startup. Hosted models also get a generous max_tokens:
reasoning models (GLM-5, o-series) spend tokens on a hidden thinking channel
first and starve the real answer if capped too low — the empty-content failure."""
def configure_model(spec: str, http_base: str, api_key: str = "", api_base: str = "") {
    # generated agentic apps (and their gate-time servers) inherit the choice;
    # cleared on non-hosted modes so a mid-session switch doesn't linger
    os.environ["JAC_AI_MODEL"] = spec if api_key else "";
    os.environ["JAC_AI_API_KEY"] = api_key;
    os.environ["JAC_AI_API_BASE"] = api_base if api_key else "";
    if http_base {
        m = Model(
            model_name=(spec.split("/")[-1] if spec else "gemma4:e4b"),
            api_key="local",
            config={"http_client": True, "api_base": http_base, "native_tools": True}
        );
    } elif api_key or (spec and ("/" in spec) and (not spec.startswith("ollama"))
                       and (key_env_for(spec)["present"] == "1")) {
        # hosted provider — litellm resolves the provider from the spec prefix
        # (zai/..., openai/..., anthropic/...). Key rides on every call when
        # given; with no key litellm falls back to the provider's env var
        # (validate_environment-confirmed). api_base override = coding-plan /
        # gateway endpoints (e.g. Z.ai Coding Plan via openai/<model>)
        os.environ["JAC_AI_MODEL"] = spec;
        os.environ["JAC_AI_API_BASE"] = api_base;
        cfg: dict[str, any] = {"native_tools": True};
        if api_base { cfg["api_base"] = api_base; }
        cp: dict[str, int] = {"max_tokens": 8000};
        if api_key { m = Model(model_name=spec, api_key=api_key, config=cfg, call_params=cp); }
        else { m = Model(model_name=spec, config=cfg, call_params=cp); }
    } elif spec {
        m = Model(
            model_name=spec,
            config={"native_tools": True},
            call_params={"think": False}
        );
    } else { return; }
    minicoder.llm = m;
    fullstack.llm = m;
    agent.llm = m;
}


def ollama_models -> list[str] {
    try {
        r = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=10);
        names: list[str] = [];
        for line in (r.stdout or "").split("\n")[1:] {
            t = line.strip().split();
            if t { names.append(str(t[0])); }
        }
        return names;
    } except Exception { return []; }
}

"""Ask litellm how the key should be stored for a spec: the provider's env
var name (validate_environment) and whether it is already set."""
def key_env_for(spec: str) -> dict[str, str] {
    if spec.startswith("zai/") {
        # litellm's env map doesn't cover zai (reports always-present) — check directly
        return {"name": "ZAI_API_KEY", "present": ("1" if os.environ.get("ZAI_API_KEY", "") else "")};
    }
    try {
        import litellm;
        vfn = getattr(litellm, "validate_environment");
        v = vfn(spec);
        missing = [str(k) for k in v.get("missing_keys", [])];
        present = "1" if v.get("keys_in_environment", False) else "";
        return {"name": (missing[0] if missing else ""), "present": present};
    } except Exception {}
    return {"name": "", "present": ""};
}

def _ask_key(saved_key: str, env_name: str = "", env_present: str = "") -> dict[str, str] {
    hint = "";
    if env_present { hint = " [blank = use $" + (env_name or "env key") + "]"; }
    elif saved_key { hint = " [blank = keep saved ····" + saved_key[-4:] + "]"; }
    key = "";
    try { key = getpass.getpass("  API key (hidden)" + hint + " > ").strip(); }
    except (EOFError, KeyboardInterrupt) {}
    if key { return {"key": key, "from_env": ""}; }
    if env_present { return {"key": "", "from_env": "1"}; }
    return {"key": saved_key, "from_env": ""};
}

"""Local path: pick an installed ollama model by number, or type any name."""
def ask_local -> dict[str, str] {
    models = ollama_models();
    console.print("  [bold]Local model (ollama)[/bold] [dim]— free, private, offline[/dim]");
    console.print("    [dim]default [green]gemma4:e4b[/green] (~4B, ~10 GB) runs the whole harness on one[/dim]");
    console.print("    [dim]consumer GPU or Apple-silicon laptop — served-and-verified backends in[/dim]");
    console.print("    [dim]~20 s, plus fullstack apps, auth/multi-user, and agentic (by-llm) apps.[/dim]");
    console.print("    [dim]gemma4:e2b (~2B) also clears every route; qwen3:8b etc. work too.[/dim]");
    i = 1;
    for mname in models {
        star = " [green]←[/green]" if mname.startswith("gemma4:e4b") else "";
        console.print(f"    [orange3]{i}.[/orange3] {mname}{star}");
        i += 1;
    }
    if not models {
        console.print("    [dim](no models installed yet — `ollama pull gemma4:e4b`)[/dim]");
    }
    console.print("    [dim]…or type any ollama model name (e.g. qwen3:8b)[/dim]");
    choice = "";
    try { choice = input("  pick [gemma4:e4b] > ").strip(); } except (EOFError, KeyboardInterrupt) {}
    name = "gemma4:e4b";
    if choice {
        if choice.isdigit() and (0 < int(choice) <= len(models)) { name = models[int(choice) - 1]; }
        else { name = choice.replace("ollama_chat/", ""); }
    }
    return {"model": "ollama_chat/" + name, "api_key": "", "http_base": "", "api_base": ""};
}

"""Z.ai GLM Coding Plan: subscription key + your choice of GLM model, routed
through the plan's OpenAI-compatible coding endpoint."""
def ask_zai(saved_key: str) -> dict[str, str] {
    p = PRESETS["zai-code"];
    console.print("  [bold]Z.ai GLM Coding Plan[/bold] [dim]— subscription key, flat monthly[/dim]");
    console.print("    [dim]models: glm-4.7 · glm-5.1 · glm-5-turbo   endpoint: " + p["base"] + "[/dim]");
    mdl = "";
    try { mdl = input("  GLM model [glm-4.7] > ").strip(); } except (EOFError, KeyboardInterrupt) {}
    mdl = mdl or "glm-4.7";
    zai_env = "1" if os.environ.get("ZAI_API_KEY", "") else "";
    console.print("    [dim]key storage: paste your plan key below (config.json, 0600) or export ZAI_API_KEY[/dim]");
    kr = _ask_key(saved_key, "ZAI_API_KEY", zai_env);
    key = kr["key"];
    if kr["from_env"] { key = os.environ.get("ZAI_API_KEY", ""); }
    if not key { return {}; }
    return {"model": "openai/" + mdl, "api_key": key, "http_base": "", "api_base": p["base"],
            "key_from_env": kr["from_env"]};
}

"""Custom litellm config: any provider/model spec + key + optional base URL —
anything litellm accepts works here."""
def ask_custom(saved_key: str) -> dict[str, str] {
    console.print("  [bold]Custom litellm[/bold] [dim]— any provider/model spec litellm accepts[/dim]");
    console.print("    [dim]spec examples:  zai/glm-4.7 · openai/gpt-5.2-mini · anthropic/claude-haiku-4-5[/dim]");
    console.print("    [dim]                gemini/gemini-2.5-flash · groq/llama-3.3-70b · openrouter/…[/dim]");
    console.print("    [dim]base URL: any OpenAI-compatible server or gateway with spec openai/<model>[/dim]");
    console.print("    [dim]          (vLLM · LM Studio · llama.cpp · coding plans, e.g. " + PRESETS["zai-code"]["base"] + ")[/dim]");
    spec = "";
    while not spec {
        try { spec = input("  litellm spec (provider/model) > ").strip(); }
        except (EOFError, KeyboardInterrupt) { return {}; }
        if spec and ("/" not in spec) {
            console.print("  [red]needs a litellm provider prefix[/red] [dim]— see docs.litellm.ai/docs/providers[/dim]");
            spec = "";
        }
    }
    env = key_env_for(spec);
    if env["name"] or env["present"] {
        where = ("$" + env["name"]) if env["name"] else "the provider's env var";
        found = " — [green]found in your environment[/green]" if env["present"] else "";
        console.print("    [dim]key storage: litellm reads " + where + found + "; or paste below (config.json, 0600)[/dim]");
    }
    kr = _ask_key(saved_key, env["name"], env["present"]);
    if (not kr["key"]) and (not kr["from_env"]) { return {}; }
    base = "";
    try { base = input("  base URL override [blank = provider default] > ").strip(); }
    except (EOFError, KeyboardInterrupt) {}
    return {"model": spec, "api_key": kr["key"], "http_base": "", "api_base": base,
            "key_from_env": kr["from_env"]};
}

"""The model config screen (/model or /config): local ollama, Z.ai Coding
Plan, or any custom litellm spec + base URL. Returns {} on cancel."""
def model_config(cur: str, saved_key: str, intro: bool = False) -> dict[str, str] {
    if intro {
        console.print("[bold]Choose your model[/bold] [dim]— change any time with /model[/dim]");
        console.print("  [dim]The harness carries the discipline, so a small local model is enough:[/dim]");
        console.print("  [dim]gemma4 (~4B) on your own machine builds served-and-verified Jac in ~20 s.[/dim]");
        console.print("  [dim]Prefer a hosted model? A coding plan or any litellm API works too.[/dim]");
    } else {
        console.print("[bold]Model config[/bold]" + (f" [dim]— current: {cur}[/dim]" if cur else ""));
    }
    console.print("  [orange3]1.[/orange3] Local (ollama) [dim]— free, private, offline; gemma4:e4b default[/dim]");
    console.print("  [orange3]2.[/orange3] Z.ai Coding Plan [dim]— subscription key; glm-4.7 / glm-5.1 / …[/dim]");
    console.print("  [orange3]3.[/orange3] Other API [dim]— any litellm provider/model + key (+ base URL)[/dim]");
    console.print("  [dim]saved to " + CONF_PATH + " (chmod 600)[/dim]");
    choice = "";
    try { choice = input("  1/2/3 > ").strip(); }
    except (EOFError, KeyboardInterrupt) { return {}; }
    if choice == "1" { return ask_local(); }
    if choice == "2" { return ask_zai(saved_key); }
    if choice == "3" { return ask_custom(saved_key); }
    if intro and (not choice) {
        # first run, no choice → default local so the TUI is usable immediately
        return ask_local();
    }
    return {};
}

"""First run: the config screen with a capability intro; blank/cancel still
falls back to the default local model so the TUI always starts usable."""
def pick_model -> dict[str, str] {
    got = model_config("", "", True);
    if got and got.get("model") { return got; }
    return {"model": "ollama_chat/gemma4:e4b", "api_key": "", "http_base": "", "api_base": ""};
}


def run_task(task: str, work_dir: str) -> minicoder.BuildResult {
    if not os.path.exists(work_dir) {
        os.makedirs(work_dir, exist_ok=True);
    }
    kind = minicoder.route(work_dir, task);
    res = minicoder.BuildResult(ok=False, stage="none", message="no result", files=[]);
    with console.status("[orange3]✳[/orange3] [bold]Routing…[/bold] [dim](ctrl+c to interrupt)[/dim]") as st {
        STATUS = st;
        try {
            if kind.startswith("fix_bug") {
                proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
                console.print(f"  [dim]│ route → fix_bug @ {proj}[/dim]");
                res = minicoder.smith_fix(task, proj);
            } elif kind.startswith("add_endpoint") {
                proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
                console.print(f"  [dim]│ route → add_endpoint @ {proj}[/dim]");
                res = minicoder.smith_add(task, proj);
            } elif fullstack.wants_frontend(task) {
                console.print("  [dim]│ route → build_fullstack (backend + UI + browser gates)[/dim]");
                res = fullstack.build_full(task, work_dir);
            } else {
                console.print(f"  [dim]│ route → build_backend[/dim]");
                res = minicoder.smith(task, work_dir);
            }
        } except Exception as e {
            # last-ditch net: any slot can still throw (a small model returning
            # invalid typed output, a transport hiccup). Show a clean, actionable
            # line instead of a stack trace — unless JACMINI_DEBUG is set, in which
            # case print the real traceback (the summary line alone is useless for
            # diagnosing a harness bug).
            if os.environ.get("JACMINI_DEBUG") {
                console.print("[red]" + traceback.format_exc() + "[/red]");
            }
            res = minicoder.BuildResult(ok=False, stage="error",
                message="hit an unexpected error — often a small model returning invalid "
                    + "output for a task this complex. Try a stronger model with /model "
                    + "(gemma4:e4b or a hosted API). Details: " + str(e)[:200],
                files=[]);
        } finally {
            STATUS = None;
        }
    }
    return res;
}


# plan.json is the durable contract written by EVERY build (backend or fullstack);
# key project detection on it. Entry differs: fullstack serves main.jac, a
# backend-only project serves its main.sv.jac.
def _find_project(work_dir: str) -> str {
    try {
        for name in sorted(os.listdir(work_dir)) {
            d = os.path.join(work_dir, name);
            if os.path.isdir(d) and (os.path.exists(os.path.join(d, "plan.json"))
                or os.path.exists(os.path.join(d, "main.jac"))
                or os.path.exists(os.path.join(d, "main.sv.jac"))) {
                return d;
            }
        }
    } except Exception {}
    return "";
}

def _entry_file(proj: str) -> str {
    if os.path.exists(os.path.join(proj, "main.jac")) { return "main.jac"; }
    if os.path.exists(os.path.join(proj, "main.sv.jac")) { return "main.sv.jac"; }
    return "main.jac";
}

"""A short project summary for the agent: the built project's path, endpoints,
and how to run it — so questions like 'how do I start it' are answered from fact."""
def project_summary(work_dir: str) -> str {
    proj = _find_project(work_dir);
    if not proj { return "No project has been built yet in this workspace (" + work_dir + ")."; }
    endpoints = "";
    kind = "backend API";
    pj = os.path.join(proj, "plan.json");
    if os.path.exists(pj) {
        try {
            with open(pj) as f { pd = json.load(f); }
            endpoints = ", ".join([str(e.get("name", "")) for e in pd.get("endpoints", [])]);
        } except Exception {}
    }
    if os.path.exists(os.path.join(proj, "frontend.cl.jac")) { kind = "fullstack web app (backend + UI)"; }
    return "Current project: " + os.path.basename(proj) + " (" + kind + ") at " + proj
        + ". Endpoints: " + (endpoints if endpoints else "(see the code)")
        + ". Run it from that directory with: jac start " + _entry_file(proj);
}

def run_hint(work_dir: str) -> str {
    proj = _find_project(work_dir);
    if not proj { return ""; }
    return "cd " + proj + " && jac start " + _entry_file(proj);
}

"""Print a byLLM streaming generator token-by-token. Markup is disabled so a
stray '[' in the text isn't eaten by rich. Falls back to a plain print if the
transport didn't actually stream (returned a whole string)."""
def stream_out(gen: any) -> str {
    got = "";
    try {
        for tok in gen {
            console.print(str(tok), end="", markup=False, highlight=False);
            got = got + str(tok);
        }
    } except Exception {
        if (not got) and isinstance(gen, str) { console.print(gen, markup=False); got = gen; }
    }
    console.print("");
    return got;
}

"""The conversational turn: understand the message, then either answer it
(streamed) or narrate + run the task-graph + wrap up (streamed)."""
def handle_message(line: str, work_dir: str) {
    if not os.path.exists(work_dir) { os.makedirs(work_dir, exist_ok=True); }
    proj = project_summary(work_dir);
    intent = agent.Intent();
    with console.status("[orange3]✳[/orange3] [dim]thinking…[/dim]") as _st {
        try { intent = agent.classify_intent(line, proj); } except Exception {}
    }
    if (not intent.kind) or (intent.kind == "chat") {
        agent_head();
        try { stream_out(agent.chat_reply(line, proj)); }
        except Exception as e { console.print("[dim](couldn't answer — " + str(e)[:100] + ")[/dim]"); }
        return;
    }
    agent_head();
    console.print(intent.blurb if intent.blurb else "Working on it.", markup=False, highlight=False);
    # Build from the USER'S OWN WORDS, with the rephrasing only as extra context.
    # Every downstream classifier is vocabulary-driven (wants_public / wants_auth /
    # wants_ai / plan_fidelity), and the model's rephrasing silently dropped signal
    # words: "posts to the PUBLIC timeline" came back without "public", so the
    # write endpoint was classified private while the reader stayed shared — the
    # app wrote to the user's own root and read the commons, and nothing ever
    # appeared. Never let a paraphrase decide access control.
    task = line;
    if intent.task and (intent.task.lower() not in line.lower()) {
        task = line + "\n\n(interpretation: " + intent.task + ")";
    }
    res = run_task(task, work_dir);
    outcome = ("succeeded: " + res.message) if res.ok
        else ("FAILED at " + res.stage + " — " + res.message.split("\n")[0][:200]);
    console.print("  ", end="");
    try { stream_out(agent.wrap_up(task, outcome, run_hint(work_dir) if res.ok else "")); }
    except Exception {
        # streaming wrap-up unavailable → fall back to a plain status line
        if res.ok { console.print("[green]done.[/green] [dim]" + res.message + "[/dim]", markup=True); }
        else { console.print("[red]" + outcome + "[/red]", markup=False); }
    }
}


"""The two models the template-first harness is calibrated and proven on."""
def is_gemma_e(spec: str) -> bool {
    n = spec.split("/")[-1].lower();
    return n in ["gemma4:e4b", "gemma4:e2b"];
}

"""On switching to any model other than gemma4:e4b / e2b, flag that template-first
is tuned for those two and offer model-first (autonomy). A more capable model is
otherwise held back — the code templates clobber its richer-but-valid choices.
Only prompts when autonomy is currently off and not in http-adapter mode."""
def flag_non_gemma(spec: str, http_base: str) {
    if http_base or (not spec) or is_gemma_e(spec) { return; }
    if minicoder.MODEL_FIRST {
        console.print("[dim]autonomy is on — model-first suits this model[/dim]");
        return;
    }
    console.print("[yellow]heads-up[/yellow] [dim]— the harness's template-first defaults are tuned for gemma4:e4b / e2b.[/dim]");
    console.print("[dim]On a more capable model the code templates can hold it back (they overwrite its richer choices). Model-first mode lets the model write each block, keeping it only when it compiles, with the template as fallback.[/dim]");
    ans = "";
    try { ans = input("  turn on model-first (autonomy) for this model? [y/N] > ").strip().lower(); }
    except (EOFError, KeyboardInterrupt) {}
    if ans in ["y", "yes"] {
        persist_model_first(True);
        console.print("[dim]autonomy [green]on[/green][/dim]");
    } else {
        console.print("[dim]left off — [orange3]/autonomy[/orange3] to turn it on anytime[/dim]");
    }
}


def mode_label(spec: str, http_base: str, api_key: str, api_base: str = "") -> str {
    if http_base { return "http:" + http_base; }
    if api_key {
        via = (" via " + api_base) if api_base else "";
        return (spec or "?") + " (api key ····" + api_key[-4:] + via + ")";
    }
    return spec or "ollama_chat/gemma4:e4b (default)";
}


"""Chat-transcript prompt: the user's turn is the `›` line they type on, so the
scrollback reads as a conversation rather than a stack of boxes."""
def read_line -> str {
    console.print("");
    console.print("[bold cyan]›[/bold cyan] ", end="");
    try { line = input(""); }
    except (EOFError, KeyboardInterrupt) { print(""); return "/quit"; }
    return line.strip();
}

"""Open an agent turn: the ⚒ identity marker every reply threads under."""
def agent_head() {
    console.print("");
    console.print("[bold orange3]⚒[/bold orange3] ", end="");
}


with entry {
    # silence litellm's provider-list banners
    os.environ["LITELLM_SUPPRESS_DEBUG_INFO"] = "true";
    try {
        import litellm;
        litellm.suppress_debug_info = True;
    } except Exception {}
    # let a config-supplied base URL reach litellm (coding plans / gateways)
    byllm_patch.patch_byllm_api_base();
    args = sys.argv[1:];
    work_dir = os.path.abspath(args[0]) if args else os.path.abspath("./work");

    # env > saved config > first-run picker
    conf = load_conf();
    model_spec = os.environ.get("JACMINI_MODEL", os.environ.get("SMITH_MODEL", "")) or str(conf.get("model", ""));
    api_key = os.environ.get("JACMINI_API_KEY", "") or str(conf.get("api_key", ""));
    http_base = os.environ.get("JACMINI_HTTP_BASE", os.environ.get("SMITH_HTTP_BASE", "")) or str(conf.get("http_base", ""));
    api_base = os.environ.get("JACMINI_API_BASE", "") or str(conf.get("api_base", ""));
    # autonomy preference: env wins, else the saved config (set by the installer
    # for hosted models, or by a prior /autonomy toggle)
    if os.environ.get("JACMINI_MODEL_FIRST", "") == "1" {
        minicoder.MODEL_FIRST = True;
    } elif str(conf.get("model_first", "")).lower() in ["true", "1"] {
        minicoder.MODEL_FIRST = True;
    }

    first_run = (not model_spec) and (not http_base);
    # ninja head beside the welcome text, claude-code style
    art = mascot.head_lines();
    info: list[list[str]] = [];
    info.append(["", ""]);
    info.append(["⚒ Welcome to jac-mini-coder!", "bold orange3"]);
    info.append(["a conversational Jac coding agent — ask, build, iterate", "dim"]);
    info.append(["", ""]);
    if not first_run {
        info.append(["model:     " + mode_label(model_spec, http_base, api_key, api_base), "default"]);
    }
    info.append(["workspace: " + work_dir.replace(os.path.expanduser("~"), "~"), "default"]);
    banner = Text();
    rows = max(len(art), len(info));
    for i in range(rows) {
        if i < len(art) { banner.append_text(art[i]); }
        else { banner.append(" " * len(mascot.HEAD[0])); }
        banner.append("  ");
        if (i < len(info)) and info[i][0] {
            banner.append(info[i][0], style=info[i][1]);
        }
        if i < rows - 1 { banner.append("\n"); }
    }
    console.print("");
    console.print(Panel(banner, box=richbox.ROUNDED, border_style="orange3", expand=False, padding=(0, 1)));

    if first_run {
        picked = pick_model();
        model_spec = str(picked.get("model", ""));
        api_key = str(picked.get("api_key", ""));
        api_base = str(picked.get("api_base", ""));
        persist_key = "" if str(picked.get("key_from_env", "")) else api_key;
        save_conf({"model": model_spec, "api_key": persist_key, "http_base": "", "api_base": api_base});
        console.print(f"  [dim]saved to {CONF_PATH}[/dim]");
        console.print(f"  [dim]model:[/dim] {mode_label(model_spec, http_base, api_key, api_base)}");
    }
    configure_model(model_spec, http_base, api_key, api_base);
    if first_run { flag_non_gemma(model_spec, http_base); }
    minicoder.TRACE_HOOK = render_event;

    console.print("[dim]  ask me anything, or tell me what to build · /model · /help · /quit[/dim]");
    console.print("");

    while True {
        line = read_line();
        if not line { continue; }
        if line in ("/quit", "/q", "/exit") {
            console.print("[dim]bye[/dim]");
            break;
        }
        if line == "/help" {
            console.print("[dim]/model or /config (model config screen) · /model <spec> · /api <spec|preset> [key] [base-url] · /http <base> · /dir <path> · /autonomy · /update · /quit — anything else is a task[/dim]");
            continue;
        }
        if line in ("/autonomy", "/modelfirst") {
            persist_model_first(not minicoder.MODEL_FIRST);
            if minicoder.MODEL_FIRST {
                console.print("[dim]autonomy [green]on[/green] — model-first: the model writes each block; the template is the fallback when it fails the gate (better for capable models, slower)[/dim]");
            } else {
                console.print("[dim]autonomy [orange3]off[/orange3] — template-first: standard blocks are code-authored (default; best for small local models)[/dim]");
            }
            continue;
        }
        if line in ("/model", "/config") {
            picked = model_config(mode_label(model_spec, http_base, api_key, api_base), api_key);
            if picked and picked.get("model") {
                model_spec = str(picked.get("model", ""));
                api_key = str(picked.get("api_key", ""));
                api_base = str(picked.get("api_base", ""));
                http_base = "";
                configure_model(model_spec, http_base, api_key, api_base);
                persist_key = "" if str(picked.get("key_from_env", "")) else api_key;
                save_conf({"model": model_spec, "api_key": persist_key, "http_base": "", "api_base": api_base});
                console.print(f"[dim]model → {mode_label(model_spec, http_base, api_key, api_base)}[/dim]");
                flag_non_gemma(model_spec, http_base);
            } else {
                console.print("[dim]unchanged[/dim]");
            }
            continue;
        }
        if line.startswith("/model ") {
            model_spec = line.split(" ", 1)[1].strip();
            if "/" not in model_spec { model_spec = "ollama_chat/" + model_spec; }
            http_base = "";
            api_key = "";
            api_base = "";
            configure_model(model_spec, http_base, api_key, api_base);
            save_conf({"model": model_spec, "api_key": "", "http_base": "", "api_base": ""});
            console.print(f"[dim]model → {model_spec}[/dim]");
            flag_non_gemma(model_spec, http_base);
            continue;
        }
        if line.startswith("/api ") {
            parts = [t for t in line.split(" ") if t];
            spec = parts[1].strip() if len(parts) > 1 else "";
            key = "";
            base = "";
            if spec in PRESETS {
                base = PRESETS[spec]["base"];
                spec2 = PRESETS[spec]["spec"];
                key = parts[2].strip() if len(parts) > 2 else "";
                spec = spec2;
            } else {
                if "/" not in spec {
                    console.print("[red]needs a litellm provider prefix or a preset name[/red] [dim]— e.g. /api zai/glm-4.7 · /api zai-code · see docs.litellm.ai/docs/providers[/dim]");
                    continue;
                }
                for t in parts[2:] {
                    if t.startswith("http") { base = t.strip(); }
                    else { key = t.strip(); }
                }
            }
            if not key {
                env = key_env_for(spec);
                if env["present"] {
                    console.print("[dim]using " + (("$" + env["name"]) if env["name"] else "the provider env key") + " from your environment[/dim]");
                } else {
                    if env["name"] {
                        console.print("[dim]key storage: litellm reads $" + env["name"] + " — or paste below (config.json, 0600)[/dim]");
                    }
                    try { key = getpass.getpass("API key (hidden) > ").strip(); } except (EOFError, KeyboardInterrupt) {}
                    if not key {
                        console.print("[red]no key given[/red]");
                        continue;
                    }
                }
            }
            model_spec = spec;
            api_key = key;
            api_base = base;
            http_base = "";
            configure_model(model_spec, http_base, api_key, api_base);
            save_conf({"model": model_spec, "api_key": api_key, "http_base": "", "api_base": api_base});
            console.print(f"[dim]model → {mode_label(model_spec, http_base, api_key, api_base)}[/dim]");
            flag_non_gemma(model_spec, http_base);
            continue;
        }
        if line.startswith("/http ") {
            http_base = line.split(" ", 1)[1].strip();
            configure_model(model_spec, http_base, api_key, api_base);
            save_conf({"model": model_spec, "api_key": api_key, "http_base": http_base, "api_base": api_base});
            console.print(f"[dim]http mode → {http_base}[/dim]");
            continue;
        }
        if line == "/update" {
            with console.status("[orange3]✳[/orange3] [bold]Updating…[/bold]") as _st {
                if os.path.isdir(os.path.join(os.getcwd(), ".git")) {
                    r = subprocess.run(["git", "pull", "--ff-only"], capture_output=True, text=True, timeout=120);
                    out = ((r.stdout or "") + (r.stderr or "")).strip();
                    console.print("[dim]" + "\n".join(out.split("\n")[-3:]) + "[/dim]");
                    subprocess.run(["jac", "install"], capture_output=True, text=True, timeout=600);
                    ok_up = (r.returncode == 0);
                } else {
                    r = subprocess.run(["bash", "-c",
                        "curl -fsSL https://github.com/jaseci-labs/jac-mini-coder/releases/latest/download/install.sh | bash"],
                        capture_output=True, text=True, timeout=900);
                    out = ((r.stdout or "") + (r.stderr or "")).strip();
                    console.print("[dim]" + "\n".join(out.split("\n")[-4:]) + "[/dim]");
                    ok_up = (r.returncode == 0);
                }
            }
            if ok_up {
                console.print("[green]updated[/green] [dim]— restart jac-mini-coder to load the new version[/dim]");
            } else {
                console.print("[red]update failed[/red] [dim]— see output above[/dim]");
            }
            continue;
        }
        if line.startswith("/dir ") {
            work_dir = os.path.abspath(line.split(" ", 1)[1].strip());
            console.print(f"[dim]workspace → {work_dir}[/dim]");
            continue;
        }
        console.print("");
        try {
            handle_message(line, work_dir);
        } except KeyboardInterrupt {
            STATUS = None;
            console.print("[dim]— interrupted[/dim]");
        }
        console.print("");
    }
}
