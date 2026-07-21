"""jac-mini-coder — a Jac coding agent small enough for small models. ⚒

A standalone TUI over the jacsmith compiled-task-graph engine. Runs entirely
on YOUR machine: your local ollama model fills a few typed slots; the harness
— stations, templates, gates, mechanical repairs — does everything else and
verifies the result live. No cloud, no API keys, no telemetry.

    jac run main.jac                 # interactive TUI (default workspace ./work)
    jac run main.jac -- ./mydir      # pick a workspace

Commands inside the TUI:
    /model <spec>     switch local model (e.g. ollama_chat/gemma4:e4b · ollama_chat/qwen3:8b)
    /http <base>      use byllm http_client mode via the adapter (small-model boxes)
    /dir <path>       switch workspace
    /quit             exit
    anything else     a task — build, add an endpoint, or fix a bug; the router decides
"""

import os;
import sys;
import jacsmith;
import from typing { Callable }
import from jaclang.byllm.lib { Model }
import from rich.console { Console }

glob console = Console();


def render_event(rec: dict) {
    kind = str(rec.get("kind", ""));
    station = str(rec.get("station", ""));
    if kind == "slot" {
        slot = str(rec.get("slot", ""));
        if slot == "template" {
            console.print(f"  [steel_blue]⚙ template[/steel_blue] [dim]{str(rec.get('input', {}).get('signatures', ''))[:64]}[/dim]");
        } elif slot == "mech_repair" {
            console.print("  [steel_blue]⚙ mechanical repair[/steel_blue] [dim](code-derived decl fix)[/dim]");
        } else {
            ok = rec.get("gate_ok", None);
            mark = "" if ok is None else (" [green]✓[/green]" if ok else " [red]✗[/red]");
            console.print(f"  [orange3]⚒ {slot}[/orange3] [dim]{station}[/dim]{mark}");
        }
    } elif kind == "gate" {
        gate = str(rec.get("gate", ""));
        if rec.get("gate_ok", False) {
            console.print(f"  [green]✓ {gate} gate[/green]");
        } else {
            err = str(rec.get("gate_errors", "")).split("\n")[0][:100];
            console.print(f"  [red]✗ {gate} gate[/red] [dim]{err}[/dim]");
        }
    } elif kind == "run" {
        console.print("  [green bold]✓ done[/green bold]");
    }
}


def configure_model(spec: str, http_base: str) {
    if http_base {
        jacsmith.llm = Model(
            model_name=(spec.split("/")[-1] if spec else "gemma4:e4b"),
            api_key="local",
            config={"http_client": True, "api_base": http_base, "native_tools": True}
        );
    } elif spec {
        jacsmith.llm = Model(
            model_name=spec,
            config={"native_tools": True},
            call_params={"think": False}
        );
    }
}


def run_task(task: str, work_dir: str) {
    if not os.path.exists(work_dir) {
        os.makedirs(work_dir, exist_ok=True);
    }
    kind = jacsmith.route(work_dir, task);
    if kind.startswith("fix_bug") {
        proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
        console.print(f"[bold]route[/bold] → fix_bug [dim]@ {proj}[/dim]");
        res = jacsmith.smith_fix(task, proj);
    } elif kind.startswith("add_endpoint") {
        proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
        console.print(f"[bold]route[/bold] → add_endpoint [dim]@ {proj}[/dim]");
        res = jacsmith.smith_add(task, proj);
    } else {
        console.print("[bold]route[/bold] → build_backend");
        res = jacsmith.smith(task, work_dir);
    }
    if res.ok {
        console.print(f"[green bold]OK[/green bold] [dim]{res.message}[/dim]");
    } else {
        console.print(f"[red bold]FAILED[/red bold] at [red]{res.stage}[/red]");
        console.print("[dim]" + res.message[:400] + "[/dim]");
    }
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
    model_spec = os.environ.get("SMITH_MODEL", "");
    http_base = os.environ.get("SMITH_HTTP_BASE", "");
    configure_model(model_spec, http_base);
    jacsmith.TRACE_HOOK = render_event;

    console.print("");
    console.print("[bold orange3]⚒ jac-mini-coder[/bold orange3] [dim]— write Jac with your local model[/dim]");
    mode = ("http:" + http_base) if http_base else (model_spec or "ollama_chat/gemma4:e4b (default)");
    console.print(f"[dim]model[/dim] {mode}   [dim]workspace[/dim] {work_dir}");
    console.print("[dim]type a task, or /help[/dim]");
    console.print("");

    while True {
        try {
            line = input("⚒ > ").strip();
        } except (EOFError, KeyboardInterrupt) {
            console.print("[dim]bye[/dim]");
            break;
        }
        if not line { continue; }
        if line in ("/quit", "/q", "/exit") {
            console.print("[dim]bye[/dim]");
            break;
        }
        if line == "/help" {
            console.print("[dim]/model <spec> · /http <base> · /dir <path> · /quit — anything else is a task[/dim]");
            continue;
        }
        if line.startswith("/model ") {
            model_spec = line.split(" ", 1)[1].strip();
            http_base = "";
            configure_model(model_spec, http_base);
            console.print(f"[dim]model → {model_spec}[/dim]");
            continue;
        }
        if line.startswith("/http ") {
            http_base = line.split(" ", 1)[1].strip();
            configure_model(model_spec, http_base);
            console.print(f"[dim]http mode → {http_base}[/dim]");
            continue;
        }
        if line.startswith("/dir ") {
            work_dir = os.path.abspath(line.split(" ", 1)[1].strip());
            console.print(f"[dim]workspace → {work_dir}[/dim]");
            continue;
        }
        run_task(line, work_dir);
        console.print("");
    }
}
