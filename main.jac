"""jac-mini-coder — a Jac coding agent small enough for small models. ⚒

A standalone TUI over the minicoder compiled-task-graph engine. Local-first:
your ollama model fills a few typed slots; the harness — stations, templates,
gates, mechanical repairs — does everything else and verifies the result live.
Prefer a hosted model? Bring your own litellm spec + API key.

    jac run main.jac                 # interactive TUI (default workspace ./work)
    jac run main.jac -- ./mydir      # pick a workspace

Commands inside the TUI:
    /model <spec>        switch local model (e.g. ollama_chat/gemma4:e4b · ollama_chat/qwen3:8b)
    /api <spec> [key]    hosted model via litellm — provider-prefixed spec
                         (zai/glm-4.7 · openai/gpt-5.2-mini · anthropic/claude-haiku-4-5 ·
                          gemini/gemini-2.5-flash · groq/... · openrouter/...);
                         key prompted securely if omitted
    /http <base>         byllm http_client mode via the adapter (small-model boxes)
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
import minicoder;
import fullstack;
import mascot;
import from jaclang.byllm.lib { Model }
import from rich.console { Console }
import from rich.panel { Panel }
import from rich.text { Text }
import from rich { box as richbox }

glob console = Console();

glob CONF_PATH: str = os.path.join(os.path.expanduser("~"), ".jac-mini-coder", "config.json");

# live spinner handle while a task runs (rich Status); events print above it
glob STATUS: any = None;

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
        with open(CONF_PATH, "w") as f { json.dump(conf, f, indent=1); }
        os.chmod(CONF_PATH, 384);  # 0o600 — the file may hold an API key
    } except Exception {}
}


"""Claude-Code-style event lines: ⏺ action headers, ⎿ indented results."""
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
            console.print(f"[b]⏺[/b] template [dim]{str(rec.get('input', {}).get('signatures', ''))[:60]}[/dim]");
        } elif slot == "mech_repair" {
            console.print("[b]⏺[/b] mechanical repair [dim](code-derived decl fix)[/dim]");
        } else {
            ok = rec.get("gate_ok", None);
            console.print(f"[b]⏺[/b] {slot} [dim]({station})[/dim]");
            if ok is not None {
                if ok {
                    console.print("  [dim]⎿[/dim]  [green]✓ passed[/green]");
                } else {
                    err = str(rec.get("gate_errors", "")).split("\n")[0][:90];
                    console.print(f"  [dim]⎿[/dim]  [red]✗[/red] [dim]{err}[/dim]");
                }
            }
        }
    } elif kind == "gate" {
        gate = str(rec.get("gate", ""));
        if rec.get("gate_ok", False) {
            console.print(f"  [dim]⎿[/dim]  [green]✓ {gate} gate[/green]");
        } else {
            err = str(rec.get("gate_errors", "")).split("\n")[0][:90];
            console.print(f"  [dim]⎿[/dim]  [red]✗ {gate} gate[/red] [dim]{err}[/dim]");
        }
    } elif kind == "run" {
        console.print("  [dim]⎿[/dim]  [green bold]✓ done[/green bold]");
    }
}


"""Bind the chosen model into both engine modules. Three modes:
http adapter (small-model boxes) > hosted API (litellm spec + key) > local ollama."""
def configure_model(spec: str, http_base: str, api_key: str = "") {
    if http_base {
        m = Model(
            model_name=(spec.split("/")[-1] if spec else "gemma4:e4b"),
            api_key="local",
            config={"http_client": True, "api_base": http_base, "native_tools": True}
        );
    } elif api_key {
        # hosted provider — litellm resolves the provider from the spec prefix
        # (zai/..., openai/..., anthropic/...); the key rides on every call
        m = Model(model_name=spec, api_key=api_key, config={"native_tools": True});
        # generated agentic apps (and their gate-time servers) inherit the choice
        os.environ["JAC_AI_MODEL"] = spec;
        os.environ["JAC_AI_API_KEY"] = api_key;
    } elif spec {
        m = Model(
            model_name=spec,
            config={"native_tools": True},
            call_params={"think": False}
        );
    } else { return; }
    minicoder.llm = m;
    fullstack.llm = m;
}


"""First-run interactive choice: local ollama (free, private) or a hosted API."""
def pick_model -> dict[str, str] {
    console.print("[bold]Choose your model[/bold]");
    console.print("  [orange3]1.[/orange3] Local ollama [dim]— free, private (default gemma4:e4b)[/dim]");
    console.print("  [orange3]2.[/orange3] Hosted API [dim]— litellm spec + your API key (e.g. zai/glm-4.7)[/dim]");
    choice = "";
    try { choice = input("  1/2 > ").strip(); } except (EOFError, KeyboardInterrupt) { choice = "1"; }
    if choice != "2" {
        spec = "";
        try { spec = input("  model [ollama_chat/gemma4:e4b] > ").strip(); } except (EOFError, KeyboardInterrupt) {}
        if spec and ("/" not in spec) { spec = "ollama_chat/" + spec; }
        return {"model": spec or "ollama_chat/gemma4:e4b", "api_key": "", "http_base": ""};
    }
    spec = "";
    while not spec {
        try { spec = input("  litellm spec (provider/model, e.g. zai/glm-4.7) > ").strip(); }
        except (EOFError, KeyboardInterrupt) { return {"model": "", "api_key": "", "http_base": ""}; }
        if spec and ("/" not in spec) {
            console.print("  [red]needs a litellm provider prefix[/red] [dim]— zai/, openai/, anthropic/, gemini/, groq/, openrouter/ … see docs.litellm.ai/docs/providers[/dim]");
            spec = "";
        }
    }
    key = "";
    try { key = getpass.getpass("  API key (hidden) > ").strip(); } except (EOFError, KeyboardInterrupt) {}
    return {"model": spec, "api_key": key, "http_base": ""};
}


def run_task(task: str, work_dir: str) {
    if not os.path.exists(work_dir) {
        os.makedirs(work_dir, exist_ok=True);
    }
    kind = minicoder.route(work_dir, task);
    with console.status("[orange3]✳[/orange3] [bold]Routing…[/bold] [dim](ctrl+c to interrupt)[/dim]") as st {
        STATUS = st;
        try {
            if kind.startswith("fix_bug") {
                proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
                console.print(f"[b]⏺[/b] route [dim]→[/dim] fix_bug [dim]@ {proj}[/dim]");
                res = minicoder.smith_fix(task, proj);
            } elif kind.startswith("add_endpoint") {
                proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
                console.print(f"[b]⏺[/b] route [dim]→[/dim] add_endpoint [dim]@ {proj}[/dim]");
                res = minicoder.smith_add(task, proj);
            } elif fullstack.wants_frontend(task) {
                console.print("[b]⏺[/b] route [dim]→[/dim] build_fullstack [dim](backend + UI + browser gates)[/dim]");
                res = fullstack.build_full(task, work_dir);
            } else {
                console.print("[b]⏺[/b] route [dim]→[/dim] build_backend");
                res = minicoder.smith(task, work_dir);
            }
        } finally {
            STATUS = None;
        }
    }
    if res.ok {
        console.print(f"[b]⏺[/b] [green bold]OK[/green bold] [dim]{res.message}[/dim]");
    } else {
        console.print(f"[b]⏺[/b] [red bold]FAILED[/red bold] at [red]{res.stage}[/red]");
        console.print("  [dim]⎿  " + res.message[:300].split("\n")[0] + "[/dim]");
    }
}


def mode_label(spec: str, http_base: str, api_key: str) -> str {
    if http_base { return "http:" + http_base; }
    if api_key { return (spec or "?") + " (api key ····" + api_key[-4:] + ")"; }
    return spec or "ollama_chat/gemma4:e4b (default)";
}


"""Claude-Code-style bordered prompt: open the box, read inside it, close it."""
def read_line -> str {
    w = min(console.width, 100);
    console.print("[dim]╭" + "─" * (w - 2) + "╮[/dim]");
    try {
        line = input("│ > ");
    } except (EOFError, KeyboardInterrupt) {
        print("");
        console.print("[dim]╰" + "─" * (w - 2) + "╯[/dim]");
        return "/quit";
    }
    console.print("[dim]╰" + "─" * (w - 2) + "╯[/dim]");
    return line.strip();
}


with entry {
    # silence litellm's provider-list banners
    os.environ["LITELLM_SUPPRESS_DEBUG_INFO"] = "true";
    try {
        import litellm;
        litellm.suppress_debug_info = True;
    } except Exception {}
    args = sys.argv[1:];
    work_dir = os.path.abspath(args[0]) if args else os.path.abspath("./work");

    # env > saved config > first-run picker
    conf = load_conf();
    model_spec = os.environ.get("JACMINI_MODEL", os.environ.get("SMITH_MODEL", "")) or str(conf.get("model", ""));
    api_key = os.environ.get("JACMINI_API_KEY", "") or str(conf.get("api_key", ""));
    http_base = os.environ.get("JACMINI_HTTP_BASE", os.environ.get("SMITH_HTTP_BASE", "")) or str(conf.get("http_base", ""));

    first_run = (not model_spec) and (not http_base);
    # ninja head beside the welcome text, claude-code style
    art = mascot.head_lines();
    info: list[list[str]] = [];
    info.append(["", ""]);
    info.append(["⚒ Welcome to jac-mini-coder!", "bold orange3"]);
    info.append(["write Jac with your own model — verified live", "dim"]);
    info.append(["", ""]);
    if not first_run {
        info.append(["model:     " + mode_label(model_spec, http_base, api_key), "default"]);
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
        save_conf({"model": model_spec, "api_key": api_key, "http_base": ""});
        console.print(f"  [dim]saved to {CONF_PATH}[/dim]");
        console.print(f"  [dim]model:[/dim] {mode_label(model_spec, http_base, api_key)}");
    }
    configure_model(model_spec, http_base, api_key);
    minicoder.TRACE_HOOK = render_event;

    console.print("[dim]  type a task · /help for commands · /quit to exit[/dim]");
    console.print("");

    while True {
        line = read_line();
        if not line { continue; }
        if line in ("/quit", "/q", "/exit") {
            console.print("[dim]bye[/dim]");
            break;
        }
        if line == "/help" {
            console.print("[dim]/model <spec> · /api <spec> [key] · /http <base> · /dir <path> · /quit — anything else is a task[/dim]");
            continue;
        }
        if line.startswith("/model ") {
            model_spec = line.split(" ", 1)[1].strip();
            if "/" not in model_spec { model_spec = "ollama_chat/" + model_spec; }
            http_base = "";
            api_key = "";
            configure_model(model_spec, http_base, api_key);
            save_conf({"model": model_spec, "api_key": "", "http_base": ""});
            console.print(f"[dim]model → {model_spec}[/dim]");
            continue;
        }
        if line.startswith("/api ") {
            parts = line.split(" ");
            spec = parts[1].strip() if len(parts) > 1 else "";
            if "/" not in spec {
                console.print("[red]needs a litellm provider prefix[/red] [dim]— e.g. /api zai/glm-4.7 · see docs.litellm.ai/docs/providers[/dim]");
                continue;
            }
            key = parts[2].strip() if len(parts) > 2 else "";
            if not key {
                try { key = getpass.getpass("API key (hidden) > ").strip(); } except (EOFError, KeyboardInterrupt) {}
            }
            if not key {
                console.print("[red]no key given[/red]");
                continue;
            }
            model_spec = spec;
            api_key = key;
            http_base = "";
            configure_model(model_spec, http_base, api_key);
            save_conf({"model": model_spec, "api_key": api_key, "http_base": ""});
            console.print(f"[dim]model → {mode_label(model_spec, http_base, api_key)}[/dim]");
            continue;
        }
        if line.startswith("/http ") {
            http_base = line.split(" ", 1)[1].strip();
            configure_model(model_spec, http_base, api_key);
            save_conf({"model": model_spec, "api_key": api_key, "http_base": http_base});
            console.print(f"[dim]http mode → {http_base}[/dim]");
            continue;
        }
        if line.startswith("/dir ") {
            work_dir = os.path.abspath(line.split(" ", 1)[1].strip());
            console.print(f"[dim]workspace → {work_dir}[/dim]");
            continue;
        }
        console.print("");
        try {
            run_task(line, work_dir);
        } except KeyboardInterrupt {
            STATUS = None;
            console.print("[dim]— interrupted[/dim]");
        }
        console.print("");
    }
}
