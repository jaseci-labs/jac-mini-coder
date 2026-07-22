"""minicoder — the jac-mini-coder engine: compiled task-graphs for writing Jac.

The procedure of authoring a Jac backend is the program, not a prose workflow:

    plan → scaffold → declare → [DECL gates] → implement → [BUILD gate] → [RUNTIME gate] → done

Each stage is a mandatory station the walker MUST visit; each gate is a
code-owned red-check with bounded repair; each cognitive step is a tight typed
byLLM slot fed only its scoped slice. Standard blocks are code-authored
templates; mechanical repairs run before any model repair. Built so a small
LOCAL model — running entirely on your machine via ollama — writes correct,
served-and-verified Jac: the graph carries the procedure, the gates compel the
work, and the model only fills the holes only a model can fill.
"""

import os;
import re;
import subprocess;
import json;
import time;
import from typing { Callable }
import from jaclang.byllm.lib { Model, Image }

glob JAC: str = os.path.expanduser("~/.local/bin/jac");

# Backend file targets. The service layout uses main.sv.jac; the fullstack
# (web-app) layout keeps walkers in endpoints.sv.jac with main.jac as the
# mixed entry. build_fullstack swaps these for a run and restores them after.
# Access map for multi-user builds: endpoint name -> "pub" | "priv" | "shared"
# | "admin". Empty map = legacy single-user mode (walker:pub everywhere).
glob ACCESS: dict[str, str] = {};

# AI mode: the generated app itself gets a by-llm slot (ask_ai walker grounded
# in the user's own graph data), an env-aware Model glob, and byllm config.
glob AI_MODE: bool = False;

# Model-first mode (optional, off by default). Template-first is the default:
# standard blocks are code-authored and the model rarely writes impl — ideal for
# weak models that stay inside the lines. When a CAPABLE model is driving, that
# clobbers its richer-but-valid choices (e.g. a list[str] field the model typed
# more precisely). Model-first flips the order PER BLOCK: try the model's own
# block, keep it if the assembled file micro-compiles, otherwise fall back to the
# code template. The gate is the arbiter — valid-richer output survives, broken
# output gets reconciled. Slower (a model call + micro-compile per templated
# block), so it is opt-in via JACMINI_MODEL_FIRST=1 or the TUI /autonomy toggle.
glob MODEL_FIRST: bool = os.environ.get("JACMINI_MODEL_FIRST", "") == "1";

def _acc(name: str) -> str {
    return ACCESS.get(name, "pub") if ACCESS else "pub";
}

def _walker_kw(name: str) -> str {
    # authenticated walkers are plain `walker` (per-user root isolation);
    # only true public endpoints stay :pub
    return "walker:pub " if _acc(name) == "pub" else "walker ";
}

glob DECL_FILE: str = "main.sv.jac";
glob IMPL_FILE: str = "main.sv.impl.jac";
glob ENTRY_FILE: str = "main.sv.jac";
# Local by default: your ollama model writes the Jac. native_tools/think are the
# two settings gemma-family models require (see README).
glob llm: Model = Model(
    model_name="ollama_chat/gemma4:e4b",
    config={"native_tools": True},
    call_params={"think": False}
);


# ==========================================================================
# TYPES — colocated with the byLLM slots that return them (schema-build rule)
# ==========================================================================

enum FileRole { DECL, IMPL, TEST, CONFIG }
sem FileRole.DECL = "A *.jac declaration surface (archetypes + typed has + signatures).";
sem FileRole.IMPL = "A *.impl.jac body file holding `impl` blocks.";
sem FileRole.TEST = "A *.test.jac file with `test` blocks.";
sem FileRole.CONFIG = "jac.toml or another config file.";


obj FileSpec {
    has path: str = "";
    has role: FileRole = FileRole.DECL;
    has purpose: str = "";
}
sem FileSpec = "One file the backend needs.";
sem FileSpec.path = "Repo-relative path, e.g. 'models.jac' or 'create_user.impl.jac'.";
sem FileSpec.role = "The kind of file.";
sem FileSpec.purpose = "One line: what this file holds.";


obj EndpointSpec {
    has name: str = "";
    has example_json: str = "{}";
}
sem EndpointSpec = "One REST endpoint the backend must expose, with a runnable example call. Endpoints are exercised live IN ORDER, so put write endpoints before the read endpoints that verify them.";
sem EndpointSpec.name = "The endpoint name ALONE — a bare snake_case verb_noun identifier with no keywords, colons or punctuation. Use the USER'S OWN domain vocabulary, derived from their request, never copied from an example.";
sem EndpointSpec.example_json = "A JSON object string with realistic values for every required walker field, e.g. '{\"title\": \"groceries\", \"body\": \"milk\"}'. Used to smoke-test the live endpoint.";


obj BuildPlan {
    has name: str = "app";
    has summary: str = "";
    has files: list[FileSpec] = [];
    has endpoints: list[EndpointSpec] = [];
}
sem BuildPlan = "A typed plan for a Jac backend / headless API service. Enumerate EVERY file and EVERY endpoint the deliverable needs — this list is the completeness contract; nothing is built that is not planned.";
sem BuildPlan.name = "Short project name, lowercase, no spaces.";
sem BuildPlan.summary = "2-3 sentences: what the backend does, its core graph (node/edge archetypes), and its walker endpoints.";
sem BuildPlan.files = "Every file to create: decl (*.jac), body (*.impl.jac), test (*.test.jac), config.";
sem BuildPlan.endpoints = "Every `walker:pub` endpoint to expose over REST, each with a runnable example payload.";


obj DeclFile {
    has path: str = "";
    has role: FileRole = FileRole.DECL;
    has source: str = "";
}
sem DeclFile = "One authored file. DECL files hold archetypes + typed `has` + `can`/`def` SIGNATURES only. IMPL files hold `impl` blocks whose bodies are initially VALID STUBS so the scaffold compiles before real logic is filled.";
sem DeclFile.path = "Repo-relative path.";
sem DeclFile.role = "DECL, IMPL, TEST, or CONFIG.";
sem DeclFile.source = "Complete source for this file.";


obj Stub {
    has file: str = "";
    has signatures: str = "";
    has intent: str = "";
}
sem Stub = "One IMPL file whose stub bodies must be replaced with real logic.";
sem Stub.file = "The *.impl.jac path to fill.";
sem Stub.signatures = "The impl signatures this file must implement, one per line, e.g. 'impl create_user.run with Root entry'.";
sem Stub.intent = "One line: what these bodies must do.";


obj Skeleton {
    has decls: list[DeclFile] = [];
    has impl_targets: list[Stub] = [];
}
sem Skeleton = "The complete decl surface of the backend plus valid stub impl files (a COMPILING scaffold), and the list of impl files to fill with real logic.";
sem Skeleton.decls = "Every file to write now: decl (*.jac) files AND their initial stub (*.impl.jac) files AND config.";
sem Skeleton.impl_targets = "One Stub per *.impl.jac file that needs real bodies.";


obj BuildResult {
    has ok: bool = False;
    has stage: str = "";
    has message: str = "";
    has files: list[str] = [];
}


obj CheckResult {
    has ok: bool = False;
    has errors: str = "";
}


# ==========================================================================
# COGNITION — tight typed byLLM slots (arity <= 3; complex-first-arg <= 2)
# ==========================================================================

def plan_build(task: str, guide: str) -> BuildPlan by llm(temperature=0.1);
sem plan_build = "Read the user's task and produce a typed BuildPlan for a Jac backend / API service. Enumerate every file needed. Prefer a small graph: a few node/edge archetypes plus `walker:pub` endpoints.";
sem plan_build.task = "The user's request for what to build.";
sem plan_build.guide = "Jac backend conventions you must follow.";

def author_decls(plan: BuildPlan, guide: str) -> Skeleton by llm(temperature=0.1);
sem author_decls = "Given the plan, write the DECL-ONLY surface for every declaration file (archetypes + typed `has` + `can`/`def` signatures, NO statement bodies) and a matching *.impl.jac for each, whose bodies are VALID STUBS so the whole thing compiles. List every stub impl file in impl_targets.";
sem author_decls.plan = "The build plan.";
sem author_decls.guide = "Jac decl/impl conventions you must follow.";

def repair_decls(broken: str, errors: str) -> Skeleton by llm(temperature=0.1);
sem repair_decls = "The scaffold failed `jac check`. Return a corrected Skeleton. Fix ONLY what the errors name; keep everything else byte-identical.";
sem repair_decls.broken = "The current files (path-tagged) plus the impl_targets list.";
sem repair_decls.errors = "The `jac check` error output.";

def fill_impl(signatures: str, context: str) -> str by llm(temperature=0.2);
sem fill_impl = "Write the real Jac body for exactly ONE impl block — the single signature given. Output ONLY that one `impl ... { ... }` block: no other blocks, no prose, no redeclarations.";
sem fill_impl.signatures = "The ONE impl signature to implement.";
sem fill_impl.context = "The frozen decl surface + intent + the scoped Jac impl guide (+ errors and the current block when repairing).";

"""A walker endpoint's request body is a JSON OBJECT of its `has` fields. A weak
model sometimes plans `example_json` as an array ("[]") or a scalar — the runtime
gate then POSTs a malformed body and every call fails even though the generated
code is correct. Coerce to an object: unwrap a list-of-objects, else empty."""
def _normalize_example(js: str) -> str {
    try {
        v = json.loads(js);
        if isinstance(v, dict) { return json.dumps(v); }
        if isinstance(v, list) and len(v) > 0 and isinstance(v[0], dict) { return json.dumps(v[0]); }
    } except Exception {}
    return "{}";
}

glob PLAN_STOPWORDS: list[str] = [
    "build", "make", "create", "with", "that", "this", "using", "app", "application",
    "web", "site", "website", "nice", "clean", "simple", "full", "stack", "fullstack",
    "backend", "frontend", "api", "endpoint", "endpoints", "page", "user", "users",
    "multi", "login", "account", "accounts", "data", "system", "clone", "and", "for",
    "the", "from", "into", "each", "every", "show", "shows", "list", "lists", "add",
    "adds", "get", "gets", "set", "have", "has", "can", "should", "please", "want"
];

"""Did the model actually plan THIS task, or echo the guide's example?

A weak model understands the request in its summary and then emits the few-shot
example endpoints verbatim (asked for a Twitter clone → plans create_note /
list_notes). Everything downstream then passes: it compiles, serves, round-trips
and clicks through — a green build of the WRONG app. Structural gates can't see
this, so check vocabulary: the task's own domain words should appear somewhere in
the planned endpoint names. Returns "" when the plan looks on-domain."""
def plan_fidelity(task: str, plan: BuildPlan) -> str {
    words: list[str] = [];
    for w in re.findall(r"[a-zA-Z_]{4,}", task.lower()) {
        ww = str(w);
        if ww not in PLAN_STOPWORDS and ww not in words { words.append(ww); }
    }
    if not words { return ""; }
    # endpoint names ONLY — plan.name is derived from the task, so including it
    # would always match and the check could never fire
    names = " ".join([e.name.lower() for e in plan.endpoints]);
    for w in words {
        # singular/plural tolerance: 'tweets' in the task matches post_tweet
        if (w in names) or (w.rstrip("s") in names) { return ""; }
    }
    return "the planned endpoints (" + ", ".join([e.name for e in plan.endpoints])
        + ") do not mention anything from the request (" + ", ".join(words[:6])
        + ") — the model most likely echoed the example instead of planning this task";
}

"""An endpoint name must be a bare identifier. A weak model echoes the
declaration keyword into the value (`name = "walker:pub post_tweet"`), which
renders as `walker walker:pub post_tweet {` — a syntax error that also breaks
brace balance. Strip keywords/punctuation and keep the trailing identifier."""
def _normalize_ep_name(name: str) -> str {
    t: str = str(name).strip();
    t = str(re.sub(r"^\s*(walker\s*:\s*\w+|walker|def\s*:\s*\w+|def|node|obj)\s+", "", t));
    m = re.findall(r"[A-Za-z_]\w*", t);
    return str(m[-1]) if m else t;
}

"""Mechanical plan hygiene applied right after the model plans (owner=code)."""
def normalize_plan(plan: BuildPlan) {
    for e in plan.endpoints {
        e.name = _normalize_ep_name(e.name);
        e.example_json = _normalize_example(e.example_json);
    }
}

def plan_add(task: str, current: str) -> EndpointSpec by llm(temperature=0.1);
sem plan_add = "The project already exists (its decl surface is given). Plan ONE new REST endpoint that fulfils the task: its walker:pub name and a runnable example payload.";
sem plan_add.task = "What the new endpoint must do.";
sem plan_add.current = "The project's current main.sv.jac declarations.";

def author_decl_update(current: str, addition: str) -> str by llm(temperature=0.1);
sem author_decl_update = "Return the COMPLETE UPDATED main.sv.jac: the current declarations byte-identical PLUS the new walker:pub declaration (and any new node/edge archetype it needs). Declarations only — no statement bodies, every `can`/`def` ends with `;`. Never remove or alter existing declarations.";
sem author_decl_update.current = "The current main.sv.jac content.";
sem author_decl_update.addition = "The new endpoint to declare (name + example payload + intent) and the decl conventions to follow.";

def repair_impl(signatures: str, context: str) -> str by llm(temperature=0.2);
sem repair_impl = "This *.impl.jac file failed a gate. Return the COMPLETE corrected file content: one `impl` block for EVERY signature listed — never a subset (your output replaces the whole file; omitting a block deletes it). Apply fixes only where the errors indicate; keep correct blocks unchanged.";
sem repair_impl.signatures = "ALL impl signatures this file must contain, one per line.";
sem repair_impl.context = "The frozen decls + the current bodies + the gate errors + the scoped guide.";


# ==========================================================================
# MECHANISM — CODE gates (the tiered red-check ladder) + write helpers
# ==========================================================================

def _run(cmd: list[str], cwd: str) -> CheckResult {
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True);
    out = (r.stdout or "") + (r.stderr or "");
    return CheckResult(ok=(r.returncode == 0), errors=("" if r.returncode == 0 else out));
}

def _write(work_dir: str, rel: str, content: str) {
    path = os.path.join(work_dir, rel);
    parent = os.path.dirname(path);
    if parent and (not os.path.exists(parent)) {
        os.makedirs(parent, exist_ok=True);
    }
    with open(path, "w") as f {
        f.write(content);
    }
}

glob TRACE_PATH: str = os.environ.get("JACMINI_TRACE", os.environ.get("SMITH_TRACE", ""));
glob TRACE_HOOK: Callable[[dict], None] | None = None;   # live event tap — the TUI registers a renderer here

"""Flywheel tap: append one JSONL record per slot call / gate verdict.
Slot records carry full input+output; the next gate record is their free label."""
def _trace(rec: dict) {
    rec["ts"] = time.time();
    rec["model"] = os.environ.get("JACMINI_MODEL", os.environ.get("SMITH_MODEL", "default"));
    if TRACE_HOOK is not None {
        try { TRACE_HOOK(rec); } except Exception {}
    }
    if not TRACE_PATH { return; }
    with open(TRACE_PATH, "a") as f {
        f.write(json.dumps(rec) + "\n");
    }
}

def _plan_dict(plan: BuildPlan) -> dict {
    return {
        "name": plan.name,
        "summary": plan.summary,
        "files": [{"path": f.path, "role": str(f.role), "purpose": f.purpose} for f in plan.files],
        "endpoints": [{"name": e.name, "example_json": e.example_json} for e in plan.endpoints]
    };
}

"""Mechanically strip markdown code fences a model may wrap source in (owner=code guard)."""
def strip_fences(src: str) -> str {
    s = src.strip();
    if s.startswith("```") {
        lines = s.split("\n");
        lines = lines[1:];
        if lines and lines[-1].strip().startswith("```") {
            lines = lines[:-1];
        }
        return "\n".join(lines);
    }
    return s;
}

"""Cheapest gate: static antipattern lint — catches the JS-idiom drift class
mechanically with steering messages, so repair converges in one round instead
of thrashing against opaque compiler errors."""
def antipattern_lint(source: str) -> CheckResult {
    bad: list[str] = [];
    if "global " in source {
        bad.append("uses the removed `global` keyword — use a module `glob` or direct assignment");
    }
    if re.search(r"\blet\s+\w", source) {
        bad.append("JS `let` is not Jac — write `x = value;` or `x: Type = value;`");
    }
    js_fixes = [(".toLower(", ".lower("), (".toUpperCase(", ".upper("),
                (".trim(", ".strip("), (".push(", ".append("),
                (".length", "len(x)"), ("=>", "lambda / def")];
    for pair in js_fixes {
        if pair[0] in source {
            bad.append("JS idiom `" + pair[0] + "` — Jac strings/lists use Python methods: " + pair[1]);
        }
    }
    if re.search(r"(?m)^\s*(for|if|while|elif|else|try|except)\b[^{;\n]*:\s*$", source) {
        bad.append("Python colon-block syntax — Jac uses BRACES and SEMICOLONS: `for c in s { x += c; }`, `if cond { ... } else { ... }` — never `for ...:` with an indented block");
    }
    if "report self.reports" in source {
        bad.append("`report self.reports` reports the channel itself — report the VALUE instead (`report here;` in a collector); the runtime accumulates reports for you");
    }
    if ("with Root entry" in source) and re.search(r"=\s*[A-Z]\w*\(", source) and ("++>" not in source) {
        bad.append("node constructed but never CONNECTED — a detached node is invisible to reads; create with `here ++> TheNode(...)`");
    }
    if ("with Root entry" in source) and re.search(r"[A-Z]\w*\(", source)
    and ("here" not in source) {
        bad.append("this block never touches `here` — nodes connected only to each other form a DETACHED subgraph invisible to reads; anchor the creation with `report here ++> TheNode(...);` (one line)");
    }
    if source.count("{") != source.count("}") {
        bad.append("UNBALANCED BRACES (" + str(source.count("{")) + " open vs " + str(source.count("}"))
            + " close) — emit the complete block with every `{` matched by a `}`");
    }
    if bad {
        return CheckResult(ok=False,
            errors="ANTIPATTERN (this is Jac — braces+semicolons, Python-style methods, NOT JavaScript and NOT Python blocks):\n- " + "\n- ".join(bad));
    }
    return CheckResult(ok=True, errors="");
}

"""Scaffold a headless API service via `jac create --kind service`."""
def scaffold_backend(work_dir: str, name: str) -> CheckResult {
    return _run([JAC, "create", name, "--kind", "service", "--force"], work_dir);
}

def gate_check(project_dir: str, dry: bool) -> CheckResult {
    if dry { return CheckResult(ok=True, errors=""); }
    return _run([JAC, "check", "."], project_dir);
}

"""Mechanical decl repair (owner=code): the two decl-gate error classes with
deterministic fixes get them applied by code BEFORE any model repair round —
a missing endpoint decl is derivable from its EndpointSpec (fields + types from
the example payload), and a missing collector ability is a one-line insert."""
def _json_type(v: object) -> str {
    if isinstance(v, bool) { return "bool"; }
    if isinstance(v, int) { return "int"; }
    if isinstance(v, float) { return "float"; }
    if isinstance(v, list) { return "list"; }
    return "str";
}

def _first_node_type(decl_src: str) -> str {
    # line-anchored: `\bnode` also matches the word "node" inside comments
    m = re.search(r"(?m)^\s*node\s+(\w+)", decl_src);
    return str(m.group(1)) if m else "Root";
}

def _payload_fields(plan: BuildPlan) -> str {
    fields = "";
    seen_f: list[str] = [];
    for e in plan.endpoints {
        try {
            pd = json.loads(e.example_json);
            for k in pd.keys() {
                if k == "reports" or str(k) in seen_f { continue; }
                seen_f.append(str(k));
                t = _json_type(pd[k]);
                dflt = " = \"\"" if t == "str" else (" = 0" if t in ["int", "float"] else " = []");
                fields = fields + "    has " + str(k) + ": " + t + dflt + ";\n";
            }
        } except Exception {}
    }
    return fields;
}

"""Derive the domain node name mechanically: first write endpoint's last
name segment, capitalized (create_note -> Note)."""
def _derive_node_name(plan: BuildPlan) -> str {
    for e in plan.endpoints {
        if not _is_read_endpoint(e.name) {
            seg = e.name.split("_")[-1];
            if seg { return seg[0].upper() + seg[1:]; }
        }
    }
    return "Item";
}

"""Drop top-level lines that aren't Jac decl grammar — degenerate model fills
leave bare junk words ('declarations', 'broken') that kill the compile while
everything around them is mechanically sound."""
def _scrub_decl_junk(src: str) -> str {
    out: list[str] = [];
    depth = 0;
    in_doc = False;
    for line in src.split("\n") {
        if line.count("\"\"\"") % 2 == 1 { in_doc = not in_doc; out.append(line); continue; }
        s = line.strip();
        if depth == 0 and (not in_doc) and s
        and (re.match(r"^(node\b|edge\b|walker\b|import\b|def\b|glob\b|sem\b|obj\b|enum\b|#|\}|\{)", s) is None) {
            continue;
        }
        out.append(line);
        depth = depth + line.count("{") - line.count("}");
    }
    return "\n".join(out);
}

def mechanical_decl_repair(sk: Skeleton, plan: BuildPlan, errors: str) -> bool {
    changed = False;
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        scrubbed = _scrub_decl_junk(d.source);
        if scrubbed != d.source {
            d.source = scrubbed;
            changed = True;
        }
        # step 0: a decl surface with NO node archetype cannot support walkers,
        # collectors, or reports typing — synthesize the domain node first
        if (not re.search(r"(?m)^\s*node\s+\w+", d.source)) and plan.endpoints {
            nn = _derive_node_name(plan);
            d.source = "node " + nn + " {\n" + _payload_fields(plan) + "}\n\n" + d.source;
            changed = True;
        }
        node_t = _first_node_type(d.source);
        # NODE-FIELD COMPLETENESS: every payload field across all endpoints must
        # exist on the node — walker templates construct with them
        if node_t != "Root" {
            m2 = re.search(r"(?m)^\s*node\s+" + node_t + r"\s*\{([\s\S]*?)\}", d.source);
            if m2 {
                body2 = str(m2.group(1));
                missing_f = "";
                seen2: list[str] = [];
                for e in plan.endpoints {
                    try {
                        pd2 = json.loads(e.example_json);
                        for k in pd2.keys() {
                            kk = str(k);
                            if kk == "reports" or kk in seen2 { continue; }
                            seen2.append(kk);
                            if re.search(r"\bhas\s+" + kk + r"\s*:", body2) is None {
                                t2 = _json_type(pd2[k]);
                                dflt2 = " = \"\"" if t2 == "str" else (" = 0" if t2 in ["int", "float"] else " = []");
                                missing_f = missing_f + "    has " + kk + ": " + t2 + dflt2 + ";\n";
                            }
                        }
                    } except Exception {}
                }
                if missing_f {
                    d.source = d.source.replace(str(m2.group(0)),
                        "node " + node_t + " {\n" + body2.rstrip() + "\n" + missing_f + "}", 1);
                    changed = True;
                }
            }
        }
        # COMPLETENESS: synthesize a missing walker:pub from its EndpointSpec
        for e in plan.endpoints {
            if ("walker:pub " + e.name) in d.source { continue; }
            if e.name not in errors { continue; }
            fields = "";
            try {
                pd = json.loads(e.example_json);
                for k in pd.keys() {
                    if k == "reports" { continue; }
                    t = _json_type(pd[k]);
                    dflt = " = \"\"" if t == "str" else (" = 0" if t in ["int", "float"] else " = []");
                    fields = fields + "    has " + str(k) + ": " + t + dflt + ";\n";
                }
            } except Exception {}
            collector = ("    can collect with " + node_t + " entry;\n") if _is_read_endpoint(e.name) else "";
            d.source = d.source.rstrip() + "\n\n" + _walker_kw(e.name) + e.name + " {\n" + fields
                + "    has reports: list[" + node_t + "] = [];\n"
                + "    can run with Root entry;\n" + collector + "}\n";
            changed = True;
        }
        # READ-SHAPE: inject the missing collector ability into the walker block
        if "READ-SHAPE" in errors {
            for wm in re.finditer(r"(walker(?::\w+)?\s+(\w+)\s*\{)", d.source) {
                wname = str(wm.group(2));
                if _is_read_endpoint(wname) and (wname in errors) {
                    blk_start = wm.end();
                    depth = 1;
                    i = blk_start;
                    while i < len(d.source) and depth > 0 {
                        if d.source[i] == "{" { depth += 1; }
                        elif d.source[i] == "}" { depth -= 1; }
                        i += 1;
                    }
                    body = d.source[blk_start:i-1];
                    # inserting a Root-entry "collector" fixes nothing and loops
                    # forever — only insert when a real node type exists
                    if node_t != "Root"
                    and (not re.search(r"can\s+\w+\s+with\s+(?!Root)\w+\s+entry", body)) {
                        insert = "    can collect with " + node_t + " entry;\n";
                        d.source = d.source[:i-1] + insert + d.source[i-1:];
                        changed = True;
                    }
                }
            }
        }
    }
    return changed;
}

"""The DECLARE station's full gate: 5d completeness + impl-completeness (stubs
count) — both always, even dry — then compile."""
def decl_gates(project_dir: str, plan: BuildPlan, sk: Skeleton, dry: bool) -> CheckResult {
    comp = gate_completeness(plan, sk);
    if not comp.ok { return comp; }
    shape = gate_read_shape(sk);
    if not shape.ok { return shape; }
    ic = gate_impl_complete(sk, False);
    if not ic.ok { return ic; }
    return gate_check(project_dir, dry);
}

"""The IMPLEMENT station's full gate: JS-idiom lint, impl-completeness incl.
empty-body/clobber (always, even dry), then full compile."""
def impl_gates(project_dir: str, sk: Skeleton, dry: bool) -> CheckResult {
    for d in sk.decls {
        if ".impl." in d.path {
            lint = antipattern_lint(d.source);
            if not lint.ok { return lint; }
        }
    }
    ic = gate_impl_complete(sk, True);
    if not ic.ok { return ic; }
    return gate_check(project_dir, dry);
}

def gate_test(work_dir: str, dry: bool) -> CheckResult {
    if dry { return CheckResult(ok=True, errors=""); }
    return _run([JAC, "test", "."], work_dir);
}

glob SERVE_PORT: int = 8901;

glob READ_VERBS: list[str] = ["list", "get", "read", "fetch", "all", "show", "count", "total"];

"""Leaf string values (len>=3) of a parsed JSON payload — the data a write
endpoint put into the graph, which a later read endpoint must surface."""
def _leaf_strings(o: object) -> list[str] {
    out: list[str] = [];
    if isinstance(o, str) {
        if len(o) >= 3 { out.append(o); }
    } elif isinstance(o, dict) {
        for v in o.values() { out.extend(_leaf_strings(v)); }
    } elif isinstance(o, list) {
        for v in o { out.extend(_leaf_strings(v)); }
    }
    return out;
}

glob AGG_VERBS: list[str] = ["count", "total", "sum", "num_"];

"""Aggregate-style reads (count_x, total_x) return a NUMBER, not the written
content — they get a numeric scenario assertion instead of a substring one."""
def _is_agg_endpoint(name: str) -> bool {
    lowered = name.lower();
    return any([lowered.startswith(v) or ("_" + v) in lowered for v in AGG_VERBS]);
}

def _is_read_endpoint(name: str) -> bool {
    lowered = name.lower();
    return any([lowered.startswith(v) or ("_" + v) in lowered for v in READ_VERBS]);
}

def _curl_json(url: str, payload: str, token: str = "") -> str {
    cmd = ["curl", "-s", "-X", "POST", url, "-H", "Content-Type: application/json", "-d", payload];
    if token {
        cmd = cmd[:4] + ["-H", "Authorization: Bearer " + token] + cmd[4:];
    }
    r = subprocess.run(cmd, capture_output=True, text=True);
    return r.stdout or "";
}

"""RUNTIME gate (owner=code): serve the backend and exercise EVERY planned endpoint
with its example payload. A 2xx `ok:true` per endpoint is the red-check — the build
oracle cannot see runtime faults; this can."""
def gate_serve(project_dir: str, endpoints: list[EndpointSpec], dry: bool, wait_s: int = 30) -> CheckResult {
    if dry { return CheckResult(ok=True, errors=""); }
    base = "http://localhost:" + str(SERVE_PORT);
    subprocess.run(["pkill", "-f", "jac start .* --port " + str(SERVE_PORT)], capture_output=True);
    srv = subprocess.Popen(
        [JAC, "start", ENTRY_FILE, "--port", str(SERVE_PORT)],
        cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    );
    try {
        # poll until the auth surface answers (register 400 on empty body still proves liveness)
        up = False;
        for _ in range(wait_s) {
            time.sleep(1);
            probe = _curl_json(base + "/user/register", "{}");
            if probe { up = True; break; }
        }
        if not up { return CheckResult(ok=False, errors="RUNTIME: server never came up on " + base); }
        _curl_json(base + "/user/register",
            '{"identities":[{"type":"username","value":"smithgate"}],"credential":{"type":"password","password":"gatepw123"}}');
        login = _curl_json(base + "/user/login",
            '{"identity":{"type":"username","value":"smithgate"},"credential":{"type":"password","password":"gatepw123"}}');
        token = "";
        try { token = json.loads(login)["data"]["token"]; }
        except Exception { return CheckResult(ok=False, errors="RUNTIME: login failed: " + login[:400]); }
        fails: list[str] = [];
        written: list[str] = [];
        for e in endpoints {
            resp = _curl_json(base + "/walker/" + e.name, e.example_json, token);
            ok = False;
            try { ok = bool(json.loads(resp).get("ok", False)); }
            except Exception { ok = False; }
            if not ok {
                fails.append(e.name + " <- " + e.example_json + " -> " + resp[:300]);
            } elif _is_agg_endpoint(e.name) and written {
                # aggregate reads return a number — after the earlier writes it
                # must be nonzero
                if re.search(r"\"reports\":\s*\[[^\]]*[1-9]", resp) is None {
                    fails.append(
                        e.name + " responded ok but reported no nonzero count after earlier writes -> " + resp[:300]
                    );
                }
            } elif _is_read_endpoint(e.name) and written {
                # scenario assertion (owner=code, derived — never model-authored):
                # a read endpoint must surface at least one value an earlier write
                # endpoint's example call put into the graph. ok:true with an empty
                # payload is the compiles-serves-does-nothing failure mode.
                if not any([w in resp for w in written]) {
                    fails.append(
                        e.name + " responded ok but NONE of the data written by earlier endpoints "
                        + str(written[:4]) + " appears in its response — the read returns nothing -> " + resp[:300]
                    );
                }
            }
            if not _is_read_endpoint(e.name) {
                try { written.extend(_leaf_strings(json.loads(e.example_json))); }
                except Exception {}
            }
        }
        if fails {
            return CheckResult(ok=False, errors="RUNTIME: endpoint exercise failed:\n" + "\n".join(fails));
        }
        return CheckResult(ok=True, errors="");
    } finally {
        srv.terminate();
    }
}

def write_all(work_dir: str, sk: Skeleton, dry: bool) -> list[str] {
    written: list[str] = [];
    if dry { return [d.path for d in sk.decls]; }
    for d in sk.decls {
        _write(work_dir, d.path, d.source);
        written.append(d.path);
    }
    return written;
}

"""Normalize a decl source so inline one-liner walkers parse identically to
multi-line ones — every `{`, `}`, `;` gets its own line boundary."""
def _norm_decl(src: str) -> str {
    return src.replace("{", "{\n").replace("}", "\n}\n").replace(";", ";\n");
}

"""Stub synthesis (owner=code): generate the *.impl.jac stub file mechanically
from the declared signatures. Writing stubs is a pure function of the decl
surface — model-authored stub files were the #1 run-to-run flake."""
def synth_stub_impls(sk: Skeleton) -> str {
    lines: list[str] = [];
    seen_keys: list[str] = [];
    cur_walker = "";
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        for line in _norm_decl(d.source).split("\n") {
            w = re.match(r"\s*walker(?::\w+)?\s+(\w+)", line);
            if w { cur_walker = w.group(1); continue; }
            if line.strip().startswith("}") { cur_walker = ""; continue; }
            a = re.match(r"\s*can\s+(\w+)\s+with\s+(.+?)\s*;", line);
            if a and cur_walker {
                akey = cur_walker + "." + str(a.group(1));
                if akey in seen_keys { continue; }
                seen_keys.append(akey);
                lines.append(
                    "impl " + cur_walker + "." + a.group(1) + " with " + a.group(2)
                    + " { report None; }"
                );
                continue;
            }
            f = re.match(r"\s*def\s+(\w+)\s*\((.*?)\)\s*(?:->\s*([\w\[\]\| ]+))?\s*;", line);
            if f {
                fkey = str(f.group(1));
                if fkey in seen_keys { continue; }
                seen_keys.append(fkey);
                ret = (f.group(3) or "").strip();
                body = "return None;";
                if ret == "str" { body = "return \"\";"; }
                elif ret == "int" { body = "return 0;"; }
                elif ret == "float" { body = "return 0.0;"; }
                elif ret == "bool" { body = "return False;"; }
                elif ret.startswith("list") { body = "return [];"; }
                elif ret.startswith("dict") { body = "return {};"; }
                elif ret == "" or ret == "None" { body = "return;"; }
                sig = "impl " + f.group(1) + "(" + f.group(2) + ")";
                if ret and ret != "None" { sig += " -> " + ret; }
                lines.append(sig + " { " + body + " }");
            }
        }
    }
    return "\n\n".join(lines) + "\n";
}

"""Impl-completeness gate (owner=code): every declared ability and function
signature must have a matching `impl`; at the final (post-fill) stage an empty
`impl ... {}` body is also red. Catches the compiles-serves-does-nothing class
(a declared-but-unimplemented ability passes `jac check` silently)."""
def gate_impl_complete(sk: Skeleton, final: bool) -> CheckResult {
    # NOTE: no role filtering — model-assigned FileRole labels are noisy; the
    # syntax patterns themselves are unambiguous (impl files contain no bare
    # `can`/`def ...;` decls, decl files contain no `impl` blocks).
    needed: list[str] = [];
    cur_walker = "";
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        for line in _norm_decl(d.source).split("\n") {
            w = re.match(r"\s*walker(?::\w+)?\s+(\w+)", line);
            if w { cur_walker = w.group(1); continue; }
            if line.strip().startswith("}") { cur_walker = ""; continue; }
            a = re.match(r"\s*can\s+(\w+)\s+with", line);
            if a and cur_walker {
                needed.append(cur_walker + "." + a.group(1));
                continue;
            }
            f = re.match(r"\s*def\s+(\w+)\s*\(", line);
            if f and line.rstrip().endswith(";") and (" by " not in line) {
                # `by llm(...)` defs are complete at declaration — no impl exists
                needed.append(f.group(1));
            }
        }
    }
    have: list[str] = [];
    empties: list[str] = [];
    clobbers: list[str] = [];
    for d in sk.decls {
        for m in re.findall(r"impl\s+(\w+)\.(\w+)\s+with", d.source) {
            have.append(str(m[0]) + "." + str(m[1]));
        }
        for m in re.findall(r"impl\s+(\w+)\s*\(", d.source) {
            have.append(str(m));
        }
        if final {
            for m in re.findall(r"impl\s+(\w+\.\w+)[^{]*\{\s*\}", d.source) {
                empties.append(str(m));
            }
            for m in re.findall(r"impl\s+(\w+\.\w+)[^{]*\{[^}]*self\.\w+\s*=\s*\"", d.source) {
                clobbers.append(str(m));
            }
        }
    }
    missing = [n for n in needed if n not in have];
    problems: list[str] = [];
    if missing {
        problems.append(
            "IMPL-COMPLETENESS: these declared signatures have NO impl body: "
            + ", ".join(missing)
            + ". FIX: the Skeleton MUST also contain a DeclFile at path 'main.sv.impl.jac'"
            + " (add the whole file if it is missing) holding one `impl` block per signature,"
            + " e.g. `impl create_note.run with Root entry { report None; }`."
        );
    }
    if empties {
        problems.append(
            "EMPTY-BODY: these impls have an empty {} body — they must contain the real logic (a list walker's run must `visit [-->];`, its collector must `report here;`): "
            + ", ".join(empties)
        );
    }
    if clobbers {
        problems.append(
            "INPUT-CLOBBER: these impls assign a hardcoded string to a walker field — `has` fields carry the CALLER'S input; delete the assignment and use the field as passed: "
            + ", ".join(clobbers)
        );
    }
    if problems {
        return CheckResult(ok=False, errors="\n".join(problems));
    }
    return CheckResult(ok=True, errors="");
}

"""Read-shape gate (owner=code): a read-verb walker (list_/get_/...) that only
has Root-entry abilities can never surface node data — it needs a collector
ability on the node type it reads. Caught as a decl-shape lint so the repair
happens at DECLARE, not as a runtime mystery."""
def gate_read_shape(sk: Skeleton) -> CheckResult {
    bad: list[str] = [];
    cur_walker = "";
    non_root: dict[str, int] = {};
    walkers: list[str] = [];
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        for line in _norm_decl(d.source).split("\n") {
            w = re.match(r"\s*walker(?::\w+)?\s+(\w+)", line);
            if w {
                cur_walker = w.group(1);
                walkers.append(cur_walker);
                non_root[cur_walker] = 0;
                continue;
            }
            if line.strip().startswith("}") { cur_walker = ""; continue; }
            a = re.match(r"\s*can\s+\w+\s+with\s+(\w+)", line);
            if a and cur_walker and a.group(1) != "Root" {
                non_root[cur_walker] = non_root[cur_walker] + 1;
            }
        }
    }
    for wname in walkers {
        if _is_read_endpoint(wname) and non_root.get(wname, 0) == 0 {
            bad.append(wname);
        }
    }
    if bad {
        return CheckResult(
            ok=False,
            errors="READ-SHAPE: these read walkers only have Root-entry abilities and can never return node data: "
                + ", ".join(bad)
                + ". FIX in main.sv.jac: give each a second ability on the node type it reads, e.g. "
                + "`can collect with Note entry;` — its run ability will `visit [-->];` and the collector will `report here;`."
        );
    }
    return CheckResult(ok=True, errors="");
}

"""5d completeness gate (owner=code): every planned endpoint must be DECLARED.
Tight typed scoping silently drops deliverables nothing carries — this catches it."""
def gate_completeness(plan: BuildPlan, sk: Skeleton) -> CheckResult {
    decls = render_decls(sk);
    missing = [e.name for e in plan.endpoints
               if re.search(r"walker(?::pub)?\s+" + e.name + r"\b", decls) is None];
    if missing {
        return CheckResult(
            ok=False,
            errors="COMPLETENESS: the plan requires these endpoints but they are not declared as `walker:pub <name>` in models.jac: "
                + ", ".join(missing) + ". Add each as a walker:pub declaration with an ability signature, plus a stub impl."
        );
    }
    return CheckResult(ok=True, errors="");
}

"""Unconditional decl completeness (owner=code), run EVERY round: the domain
node, its payload fields, and one walker per plan endpoint must exist. Models
drop siblings during repairs (e2b oscillation) — the harness always restores
them; error-gated repair was too weak a trigger."""
def ensure_decl_completeness(sk: Skeleton, plan: BuildPlan) {
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        if (not re.search(r"(?m)^\s*node\s+\w+", d.source)) and plan.endpoints {
            nn = _derive_node_name(plan);
            d.source = "node " + nn + " {\n" + _payload_fields(plan) + "}\n\n" + d.source;
        }
        node_t = _first_node_type(d.source);
        if node_t == "Root" { continue; }
        m2 = re.search(r"(?m)^\s*node\s+" + node_t + r"\s*\{([\s\S]*?)\}", d.source);
        if m2 {
            body2 = str(m2.group(1));
            missing_f = "";
            seen2: list[str] = [];
            for e in plan.endpoints {
                try {
                    pd2 = json.loads(e.example_json);
                    for k in pd2.keys() {
                        kk = str(k);
                        if kk == "reports" or kk in seen2 { continue; }
                        seen2.append(kk);
                        if re.search(r"\bhas\s+" + kk + r"\s*:", body2) is None {
                            t2 = _json_type(pd2[k]);
                            dflt2 = " = \"\"" if t2 == "str" else (" = 0" if t2 in ["int", "float"] else " = []");
                            missing_f = missing_f + "    has " + kk + ": " + t2 + dflt2 + ";\n";
                        }
                    }
                } except Exception {}
            }
            if missing_f {
                d.source = d.source.replace(str(m2.group(0)),
                    "node " + node_t + " {\n" + body2.rstrip() + "\n" + missing_f + "}", 1);
            }
        }
        for e in plan.endpoints {
            if re.search(r"walker(:pub)?\s+" + e.name + r"\b", d.source) { continue; }
            fields = "";
            try {
                pd = json.loads(e.example_json);
                for k in pd.keys() {
                    if k == "reports" { continue; }
                    t = _json_type(pd[k]);
                    dflt = " = \"\"" if t == "str" else (" = 0" if t in ["int", "float"] else " = []");
                    fields = fields + "    has " + str(k) + ": " + t + dflt + ";\n";
                }
            } except Exception {}
            collector = ("    can collect with " + node_t + " entry;\n") if _is_read_endpoint(e.name) else "";
            d.source = d.source.rstrip() + "\n\n" + _walker_kw(e.name) + e.name + " {\n" + fields
                + "    has reports: list[" + node_t + "] = [];\n"
                + "    can run with Root entry;\n" + collector + "}\n";
        }
    }
}

"""Rewrite references to UNDECLARED node types onto the real one.

A weak model declares `node Tweet {...}` and then writes `has reports: list[Note]`
and `can collect with Note entry` — Note never exists. The write path then builds
one type while the read path collects another, so the app compiles, serves, and
still shows nothing (the UI gate's 'filled the form but the value never appeared').
Point every dangling node reference at the primary declared node."""
def unify_node_refs(sk: Skeleton) {
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        declared = [str(m) for m in re.findall(r"(?m)^\s*node\s+(\w+)", d.source)];
        if not declared { continue; }
        primary = declared[0];
        for ref in set([str(m) for m in re.findall(r"list\[(\w+)\]", d.source)]
                       + [str(m) for m in re.findall(r"with\s+(\w+)\s+entry", d.source)]) {
            if ref == primary { continue; }
            if ref in ["Root", "str", "int", "float", "bool", "dict", "list", "any"] { continue; }
            # NOTE: this rewrites SECONDARY declared nodes too. The block
            # templates are single-node by construction, so a walker reporting
            # one type while another collects a different one can only produce
            # the compiles-serves-shows-nothing failure.
            d.source = re.sub(r"list\[" + ref + r"\]", "list[" + primary + "]", d.source);
            d.source = re.sub(r"with\s+" + ref + r"\s+entry", "with " + primary + " entry", d.source);
        }
    }
}

# fields that name WHO acted. In an authenticated app these must come from the
# session, never from the request body — otherwise any user can type someone
# else's handle and post as them.
glob IDENTITY_FIELDS: list[str] = ["user_id", "userid", "author_id", "authorid", "author",
                                   "username", "owner", "poster", "created_by", "user"];
# a stable, unforgeable per-user handle derived from the caller's own root
glob SESSION_AUTHOR: str = "(\"u_\" + jid(root)[:8])";

def is_identity_field(f: str) -> bool {
    return f.lower() in IDENTITY_FIELDS;
}

glob AI_TWIN_WORDS: list[str] = ["assistant", "chatbot", "chat", "answer", "inquire", "query"];

"""Remove model-authored 'assistant'-style walkers (ask_assistant, chat_bot,
answer_question, ...) that duplicate the harness-owned ask_ai. ask_ai itself is
never matched. Balanced-brace removal so the whole block goes."""
def _strip_ai_twin_walkers(src: str) -> str {
    out = src;
    guard = 0;
    while guard < 12 {
        guard += 1;
        hit = None;
        for wm in re.finditer(r"walker(?::\w+)?\s+(\w+)\s*\{", out) {
            nm = str(wm.group(1));
            low = nm.lower();
            if nm == "ask_ai" { continue; }
            is_twin = low.startswith("ask") or low.startswith("assistant")
                or any([w in low for w in AI_TWIN_WORDS]);
            if is_twin { hit = wm; break; }
        }
        if hit is None { break; }
        # walk balanced braces from the block's opening {
        depth = 1;
        i = hit.end();
        while i < len(out) and depth > 0 {
            if out[i] == "{" { depth += 1; }
            elif out[i] == "}" { depth -= 1; }
            i += 1;
        }
        out = out[:hit.start()] + out[i:];
    }
    return re.sub(r"\n{3,}", "\n\n", out);
}

"""Force the mechanical scaffold invariants onto a model-authored Skeleton:
the stub impl file is code-synthesized (replacing whatever the model emitted at
that path) and impl_targets is code-derived — the model cannot drop either."""
def force_stub_file(sk: Skeleton, plan: BuildPlan) {
    for d in sk.decls {
        # strip model-echoed path-tag lines and unescape quote artifacts
        # strip model-echoed path-tag lines and JSON-escape artifacts. A small
        # model emits `has x: str = \\"\\";` (escaped quotes) straight from its typed
        # output — E0100 unterminated string, and the file never parses, so even
        # mechanical repair can't run on it.
        d.source = re.sub(r"(?m)^\s*===.*===\s*$", "", d.source)
            .replace("\\'", "'").replace('\\"', '"');
        # `edge Rel Wrote { ... }` — two identifiers is not a declaration a weak
        # model can recover from; keep the first name so the block parses
        d.source = re.sub(r"(?m)^(\s*edge\s+\w+)\s+\w+(\s*\{)", r"\1\2", d.source);
    }
    # the contract is TWO files — drop any hallucinated extras before they can
    # fail a gate (models occasionally invent main.impl.jac / helper files).
    # If the decl file came back under a wrong name, claim it rather than drop it.
    if not [d for d in sk.decls if d.path == DECL_FILE] {
        for d in sk.decls {
            if ".impl." not in d.path and ("walker" in d.source or "node " in d.source) {
                d.path = DECL_FILE;
                break;
            }
        }
    }
    if not [d for d in sk.decls if d.path == DECL_FILE] {
        # no usable decl surface came back at all — give the mechanical
        # synthesis an empty canvas; node/walker synth builds it from the plan
        sk.decls.append(DeclFile(path=DECL_FILE, role=FileRole.DECL, source=""));
    }
    sk.decls = [d for d in sk.decls if d.path == DECL_FILE];
    # BEFORE synthesizing a node for a dangling collector type: if a node is
    # already declared, point the dangling refs at IT. Otherwise we end up with
    # two nodes (the declared one + a synthesized one), the write template picks
    # the first and the reader collects the other — the app compiles, serves,
    # and shows nothing.
    unify_node_refs(sk);
    # a walker referencing an undeclared node type is a one-decl omission —
    # synthesize the node from the union of endpoint payload fields
    for d in sk.decls {
        for nt in re.findall(r"can\s+\w+\s+with\s+(?!Root)(\w+)\s+entry", _norm_decl(d.source)) {
            ntn = str(nt);
            if re.search(r"(?m)^\s*node\s+" + ntn + r"\b", d.source) { continue; }
            fields = "";
            seen_f: list[str] = [];
            for e in plan.endpoints {
                try {
                    pd = json.loads(e.example_json);
                    for k in pd.keys() {
                        if k == "reports" or str(k) in seen_f { continue; }
                        seen_f.append(str(k));
                        t = _json_type(pd[k]);
                        dflt = " = \"\"" if t == "str" else (" = 0" if t in ["int", "float"] else " = []");
                        fields = fields + "    has " + str(k) + ": " + t + dflt + ";\n";
                    }
                } except Exception {}
            }
            d.source = "node " + ntn + " {\n" + fields + "}\n\n" + d.source;
        }
    }
    ensure_decl_completeness(sk, plan);
    # AFTER completeness: the primary node may have just been synthesized, and
    # dangling refs can only be pointed at a node that exists
    unify_node_refs(sk);
    if ACCESS {
        for d in sk.decls {
            if ".impl." in d.path { continue; }
            for e in plan.endpoints {
                if ACCESS.get(e.name, "pub") != "pub" {
                    d.source = d.source.replace("walker:pub " + e.name, "walker " + e.name);
                }
            }
        }
    }
    if AI_MODE {
        # the AI runtime (llm glob + ai_answer slot) is CODE-OWNED and lives in
        # ai.jac, written at scaffold time — never in the model's repair canvas.
        # The decl only carries two grammar-clean lines: the import + the walker.
        for d in sk.decls {
            if ".impl." in d.path { continue; }
            # a capable model may author its OWN assistant walker (ask_assistant,
            # chat, answer_question, ...) that duplicates — and often mis-calls —
            # the harness-provided ask_ai. That is broken divergence: the harness
            # owns the AI endpoint, so drop the model's twin before it can fail a
            # gate. (ask_ai itself is preserved.)
            d.source = _strip_ai_twin_walkers(d.source);
            if "import from ai {" not in d.source {
                d.source = "import from ai { ai_answer }\n\n" + d.source.lstrip();
            }
            if re.search(r"walker(:pub)?\s+ask_ai\b", d.source) is None {
                kw_ai = "walker" if ACCESS else "walker:pub";
                d.source = d.source.rstrip()
                    + "\n\n" + kw_ai + " ask_ai {\n    has question: str = \"\";\n    has reports: list[str] = [];\n    can run with Root entry;\n}\n";
            }
        }
    }
    if ACCESS and ("admin" in [ACCESS.get(e.name, "") for e in plan.endpoints]) {
        for d in sk.decls {
            if ".impl." in d.path { continue; }
            if re.search(r"(?m)^\s*node\s+Account\b", d.source) is None {
                # APPEND — Account must never become the first (domain) node
                d.source = d.source.rstrip() + "\n\nnode Account { has role: str = \"member\"; }\n";
            }
            if re.search(r"walker\s+claim_admin\b", d.source) is None {
                d.source = d.source.rstrip()
                    + "\n\nwalker claim_admin {\n    has reports: list[str] = [];\n    can run with Root entry;\n}\n";
            }
        }
    }
    # DEFAULT-ENFORCEMENT: every node has-field carries a default so partial
    # constructors (templates fill only their own walker's fields) always compile
    for d in sk.decls {
        if ".impl." in d.path { continue; }
        dq = chr(34);
        d.source = re.sub(r"\b(has\s+\w+\s*:\s*str)\s*;", "\\1 = " + dq + dq + ";", d.source);
        d.source = re.sub(r"\b(has\s+\w+\s*:\s*int)\s*;", r"\1 = 0;", d.source);
        d.source = re.sub(r"\b(has\s+\w+\s*:\s*float)\s*;", r"\1 = 0.0;", d.source);
        d.source = re.sub(r"\b(has\s+\w+\s*:\s*bool)\s*;", r"\1 = False;", d.source);
        d.source = re.sub(r"\b(has\s+\w+\s*:\s*list\[[^\]]+\])\s*;", r"\1 = [];", d.source);
    }
    stub_src = synth_stub_impls(sk);
    sk.decls = [d for d in sk.decls if d.path != IMPL_FILE];
    sk.decls.append(DeclFile(path=IMPL_FILE, role=FileRole.IMPL, source=stub_src));
    sigs = "\n".join([ln.split(" {")[0] + ";" for ln in stub_src.split("\n\n") if ln.strip()]);
    sk.impl_targets = [Stub(
        file=IMPL_FILE,
        signatures=sigs,
        intent="Implement the real logic for every signature: " + plan.summary
    )];
}

"""Keep the in-memory Skeleton in sync with bodies written to disk, so the
impl-completeness gate and repair contexts see current sources, not stale stubs."""
def update_impl_source(sk: Skeleton, file: str, body: str) {
    for d in sk.decls {
        if d.path == file {
            d.source = body;
        }
    }
}

def render_decls(sk: Skeleton) -> str {
    parts: list[str] = [];
    for d in sk.decls {
        parts.append("=== " + d.path + " ===\n" + d.source);
    }
    return "\n\n".join(parts);
}

"""The frozen decl surface + this stub's intent + the scoped impl guide."""
def fill_context(sk: Skeleton, st: Stub, guide: str) -> str {
    frozen = render_decls(sk);
    return guide + "\n\n--- FROZEN DECLS ---\n" + frozen + "\n\n--- INTENT ---\n" + st.intent;
}

def block_key(sig: str) -> str {
    m = re.match(r"\s*impl\s+([\w.]+)", sig);
    return str(m.group(1)) if m else sig.strip()[:40];
}

glob IMPL_CORE_RULES: str =
"Jac core rules: braces + semicolons (NEVER Python colon-blocks, NEVER JS let/=>); "
"string/list methods are Python's (.lower(), .strip(), .append()); walker `has` fields carry the CALLER'S "
"input — use as passed, never overwrite; values leave ONLY via `report X;`.";

"""Per-block micro-guide (owner=code): each block shape gets ONLY the guidance
that shape needs — the whole-guide-per-block variant lured models into
copy-pasting unrelated patterns (get-or-create inside a collector)."""
def block_guide(sig: str) -> str {
    m = re.match(r"\s*impl\s+(\w+)\.(\w+)\s+with\s+(\w+)", sig);
    if m {
        wname = str(m.group(1));
        node_t = str(m.group(3));
        if node_t != "Root" {
            return "This is a COLLECTOR ability: it runs on each visited " + node_t
                + " node. Usually exactly `{ report here; }` — for updates assign `here.<field> = self.<field>;` first."
                + " Do NOT create nodes here, do NOT use get-or-create.";
        }
        if _is_read_endpoint(wname) {
            return "This is a READ walker's Root ability: traverse ONLY — usually exactly `{ visit [-->]; }`"
                + " (a collector ability reports the nodes; do not report or create here)."
                + " For a COUNT-style walker with no collector: `{ report len([here -->][?:<Node>]); }`.";
        }
        return "This is a WRITE walker's Root ability: create/connect from the walker's fields and report, e.g."
            + " `{ report here ++> Note(title=self.title, body=self.body); }`."
            + " Filter existing: `[here -->][?:Note][?title == self.title]`; delete: `for n in [...] { del n; }`.";
    }
    return "This is a plain function body: pure Jac (braces+semicolons), return the declared type.";
}

"""Keep ONLY the impl block that answers the requested signature.

A small model often returns the right block PLUS invented extras — function-style
`impl add_bookmark(title: str) -> Bookmark { ... }` alongside the real
`impl add_bookmark.run with Root entry { ... }`. Those extras match no declared
signature, are frequently invalid Jac, and the model re-emits them every repair
round, so the build never converges. The impl file may only contain blocks for
DECLARED signatures — enforce that mechanically here."""
def keep_requested_block(block: str, sig: str) -> str {
    want = block_key(sig);
    segs = [x.strip() for x in re.split(r"(?m)^(?=impl\s)", block) if x.strip()];
    if len(segs) <= 1 { return block; }
    for seg in segs {
        if block_key(seg) == want { return seg; }
    }
    # nothing matched the request — keep the first segment rather than all of them
    return segs[0];
}

"""Block sanitizer (owner=code): precise mechanical rewrites of known-safe model
tics — a stray `;` before the body brace, and the reports-append idiom, whose
correct form (`report X;`) is a 1:1 transform under the walker contract."""
def sanitize_block(block: str) -> str {
    block = re.sub(r"(impl[^{;\n]*);\s*\{", r"\1 {", block);
    block = re.sub(r"self\.reports\.append\((.+?)\);", r"report \1;", block);
    if ("++>" not in block) and ("with Root entry" in block) {
        # a constructed-but-unconnected node is invisible to every later read —
        # `report Note(...)` must be `report here ++> Note(...)`
        block = re.sub(r"report\s+([A-Z]\w*)\(", r"report here ++> \1(", block);
    }
    return block;
}

"""Does this walker declare a collector (non-Root entry) ability?"""
def walker_has_collector(decl_src: str, wname: str) -> bool {
    cur = "";
    for line in _norm_decl(decl_src).split("\n") {
        w = re.match(r"\s*walker(?::\w+)?\s+(\w+)", line);
        if w { cur = w.group(1); continue; }
        if line.strip().startswith("}") { cur = ""; continue; }
        if cur == wname and re.match(r"\s*can\s+\w+\s+with\s+(?!Root)\w+", line) {
            return True;
        }
    }
    return False;
}

"""Template-first blocks (owner=code): the standard shapes are KNOWN — code
writes them outright, no model call, no failure possible. The model only
authors blocks that are genuinely task-specific."""
def block_template(sig: str, decl_src: str) -> str {
    header = sig.strip().rstrip(";");
    m = re.match(r"impl\s+(\w+)\.(\w+)\s+with\s+(\w+)\s+entry", header);
    if m is None { return ""; }
    wname = str(m.group(1));
    node_t = str(m.group(3));
    # harness-owned walkers dispatch BEFORE any generic heuristic — ask_ai has
    # a has-field, so the write-run template would otherwise claim it
    if sig.strip().startswith("impl ask_ai.run") {
        nt4 = _first_node_type(decl_src);
        ser = "str(n)";
        return header + " { "
            + "parts: list[str] = []; "
            + "for n in [here -->][?:" + nt4 + "] { parts.append(" + ser + "); } "
            + "ctx = \"; \".join(parts) if parts else \"(no items yet)\"; "
            + "report ai_answer(self.question, ctx); }";
    }
    if sig.strip().startswith("impl claim_admin.run") {
        return header + " { "
            + "for r in allroots() { for a in [r -->][?:Account] { "
            + "if a.role == \"admin\" and jid(r) != jid(here) { report \"taken\"; skip; } } } "
            + "accts = [here -->][?:Account]; "
            + "if len(accts) > 0 { accts[0].role = \"admin\"; } "
            + "else { here ++> Account(role=\"admin\"); } "
            + "report \"ok\"; }";
    }
    if node_t != "Root" {
        # collector on a read walker: exactly `report here;`
        if _is_read_endpoint(wname) { return header + " { report here; }"; }
        return "";
    }
    acc = _acc(wname);
    if _is_read_endpoint(wname) {
        nt = _first_node_type(decl_src);
        if acc == "shared" and nt != "Root" {
            # commons read: one traversal of root.shared, no collector needed
            return header + " { for n in [root.shared -->][?:" + nt + "] { report n; } }";
        }
        if walker_has_collector(decl_src, wname) {
            return header + " { visit [-->]; }";
        }
        # collector-less read (count-style): report the aggregate directly
        if nt != "Root" { return header + " { report len([here -->][?:" + nt + "]); }"; }
    }
    # standard WRITE-run: the field mapping is the walker's own has-fields —
    # fully derivable, the single most-failed model block across all sweeps
    nt = _first_node_type(decl_src);
    if nt != "Root" {
        fields: list[str] = [];
        cur = "";
        for line in _norm_decl(decl_src).split("\n") {
            w2 = re.match(r"\s*walker(?::\w+)?\s+(\w+)", line);
            if w2 { cur = w2.group(1); continue; }
            if line.strip().startswith("}") { cur = ""; continue; }
            h = re.match(r"\s*has\s+(\w+)\s*:", line);
            if h and cur == wname and str(h.group(1)) != "reports" {
                # dedupe: a walker repeated in the decl surface (repair rounds,
                # duplicated blocks) would otherwise emit `User(title=..., title=...)`
                # — E0065 duplicate keyword argument, from OUR OWN template
                if str(h.group(1)) not in fields { fields.append(str(h.group(1))); }
            }
        }
        # only pass fields the NODE actually declares: a walker often carries
        # extras (new_tweet_id, user_id, ...) that the node has no parameter for
        # → E1052 'named argument does not match any parameter', from OUR template
        node_fields: list[str] = [];
        mnode = re.search(r"(?m)^\s*node\s+" + nt + r"\s*\{([\s\S]*?)\}", decl_src);
        if mnode {
            for hm in re.findall(r"\bhas\s+(\w+)\s*:", str(mnode.group(1))) {
                node_fields.append(str(hm));
            }
        }
        if node_fields { fields = [f for f in fields if f in node_fields]; }
        if fields {
            # authenticated app → the author is taken from the session
            argl: list[str] = [];
            for f in fields {
                if ACCESS and is_identity_field(f) { argl.append(f + "=" + SESSION_AUTHOR); }
                else { argl.append(f + "=self." + f); }
            }
            args = ", ".join(argl);
            acc2 = _acc(wname);
            guard = "";
            if acc2 == "admin" {
                guard = "accts = [here -->][?:Account]; "
                    + "if not (len(accts) > 0 and accts[0].role == \"admin\") "
                    + "{ report \"forbidden\"; skip; } ";
            }
            if acc2 == "shared" {
                # commons write: attach to root.shared and open it to readers
                return header + " { " + guard + "fresh = root.shared ++> " + nt + "(" + args + "); "
                    + "grant(fresh, level=ReadPerm); report fresh; }";
            }
            return header + " { " + guard + "report here ++> " + nt + "(" + args + "); }";
        }
    }
    acc3 = _acc(wname);
    if acc3 == "admin" {
        # field-less admin action (clear_x / delete_x): role guard + commons purge
        nt3 = _first_node_type(decl_src);
        if nt3 != "Root" {
            return header + " { "
                + "accts = [here -->][?:Account]; "
                + "if not (len(accts) > 0 and accts[0].role == \"admin\") "
                + "{ report \"forbidden\"; skip; } "
                + "for n in [root.shared -->][?:" + nt3 + "] { del n; } "
                + "report \"cleared\"; }";
        }
    }
    return "";
}

"""Scope gate errors to one block (owner=code): a block being repaired sees only
the error lines that mention it — full dumps steer repairs at the wrong block."""
def scope_errors(errors: str, key: str) -> str {
    toks = key.split(".");
    lines = [l for l in errors.split("\n") if any([t in l for t in toks])];
    return "\n".join(lines) if lines else errors;
}

"""Per-signature block fills (the impl separation doing the work): the model
writes ONE small block per call; code owns targeting, assembly, dedup, and
sibling preservation. On repair, only blocks named in the errors are re-filled
(all if none match). Long-generation failure modes cannot occur."""
def fill_impl_blocks(
    sk: Skeleton, st: Stub, errors: str, prev: dict[str, str],
    station: str, round_n: int,
    project_dir: str = "", dry: bool = True, existing: str = ""
) -> dict[str, str] {
    sigs = [s.strip() for s in st.signatures.split("\n") if s.strip()];
    out: dict[str, str] = {};
    for s in sigs {
        k = block_key(s);
        if k in prev { out[k] = prev[k]; }
    }
    targets: list[str] = [];
    if not prev {
        targets = [block_key(s) for s in sigs];
    } else {
        failing = [k for k in out.keys()
                   if (k in errors) or (k.split(".")[-1] in errors) or (k.split(".")[0] in errors)];
        targets = failing if failing else [block_key(s) for s in sigs];
    }
    frozen = "";
    for d in sk.decls {
        if ".impl." not in d.path { frozen = frozen + d.source + "\n"; }
    }
    for s in sigs {
        k = block_key(s);
        if k not in targets { continue; }
        # 1 · template: standard shapes are code-authored. In the default
        #     (template-first) mode an available template is infallible and the
        #     model never runs. In MODEL_FIRST mode the template is kept as a
        #     fallback and the model gets first shot below.
        tpl = block_template(s, frozen);
        if tpl and (not MODEL_FIRST) {
            _trace({"station": station, "kind": "slot", "slot": "template", "round": round_n,
                    "input": {"file": st.file, "signatures": s}, "output": tpl});
            out[k] = tpl;
            continue;
        }
        # 2 · best-of-N model fills; a block is accepted ONLY if the assembled
        #     file micro-compiles with it in place (idiom-agnostic red-check)
        base_ctx = IMPL_CORE_RULES + "\n" + block_guide(s)
            + "\n\n--- DECLARATIONS ---\n" + frozen + "\n--- INTENT ---\n" + st.intent;
        if errors { base_ctx = base_ctx + "\n\n--- ERRORS TO FIX ---\n" + scope_errors(errors, k); }
        if out.get(k, "") { base_ctx = base_ctx + "\n\n--- CURRENT BLOCK (rewrite it corrected) ---\n" + out[k]; }
        feedback = "";
        block = "";
        block_ok = False;
        for attempt in range(3) {
            ctx = base_ctx + (("\n\n--- YOUR PREVIOUS ATTEMPT FAILED ---\n" + feedback) if feedback else "");
            block = sanitize_block(keep_requested_block(strip_fences(fill_impl(s, ctx)), s));
            lint = antipattern_lint(block);
            if not lint.ok { feedback = lint.errors; continue; }
            if dry or (not project_dir) { block_ok = True; break; }
            cand = dict(out);
            cand[k] = block;
            cfile = merge_impl_blocks(existing, cand) if existing else assemble_impl(st, cand);
            _write(project_dir, st.file, cfile);
            mc = gate_check(project_dir, dry);
            if mc.ok { block_ok = True; break; }
            feedback = scope_errors(mc.errors, k);
        }
        # MODEL_FIRST fallback: the model's block never passed the gate, but a
        # code template exists — take it (the gate is the arbiter; the model's
        # magic only survives when it actually compiles+verifies).
        if (not block_ok) and tpl {
            _trace({"station": station, "kind": "slot", "slot": "template_fallback", "round": round_n,
                    "input": {"file": st.file, "signatures": s}, "output": tpl});
            out[k] = tpl;
            continue;
        }
        # monotonic acceptance: never replace a previously-accepted block with
        # one that still fails after all samples
        if feedback and out.get(k, "") and antipattern_lint(out[k]).ok {
            lint2 = antipattern_lint(block);
            if not lint2.ok { block = out[k]; }
        }
        _trace({"station": station, "kind": "slot", "slot": "fill_impl", "round": round_n,
                "input": {"file": st.file, "signatures": s}, "output": block});
        out[k] = block;
    }
    return out;
}

"""All impl signatures present in a skeleton's impl file — the repair-leverage
fallback when a mutation's new-signature worklist is empty (idempotent re-adds,
prior failed attempts)."""
def all_impl_sigs(sk: Skeleton) -> str {
    sigs: list[str] = [];
    for d in sk.decls {
        if ".impl." not in d.path { continue; }
        for seg0 in re.split(r"(?m)^(?=impl\s)", d.source) {
            seg = str(seg0).strip();
            if seg { sigs.append(seg.split("{")[0].strip().rstrip(";") + ";"); }
        }
    }
    return "\n".join(sigs);
}

"""Merge-assembly for mutation graphs: existing blocks stay byte-identical
unless a filled block replaces them by key; genuinely-new blocks append."""
def merge_impl_blocks(existing: str, blocks: dict[str, str]) -> str {
    segs = [s.strip() for s in re.split(r"(?m)^(?=impl\s)", existing) if s.strip()];
    used: list[str] = [];
    parts: list[str] = [];
    for seg in segs {
        k = block_key(seg);
        if k in blocks and blocks[k] {
            parts.append(blocks[k]);
            used.append(k);
        } else {
            parts.append(seg);
        }
    }
    for k in blocks.keys() {
        if (k not in used) and blocks[k] {
            parts.append(blocks[k]);
        }
    }
    return "\n\n".join(parts) + "\n";
}

"""Code-owned file assembly: stub order, first-writer-wins dedup."""
def assemble_impl(st: Stub, blocks: dict[str, str]) -> str {
    sigs = [s.strip() for s in st.signatures.split("\n") if s.strip()];
    seen: list[str] = [];
    parts: list[str] = [];
    for s in sigs {
        k = block_key(s);
        if k in seen { continue; }
        seen.append(k);
        if blocks.get(k, "") { parts.append(blocks[k]); }
    }
    return "\n\n".join(parts) + "\n";
}


# ==========================================================================
# THE SPINE — mandatory stations; the walker cannot reach `done` without
# passing every gate.
# ==========================================================================

node ScaffoldSt {}
node DeclareSt {}
node ImplementSt {}
node VerifySt {}
node DoneSt {}


walker build_backend {
    has task: str = "";
    has work_dir: str = "";
    has project_dir: str = "";
    has plan: BuildPlan = BuildPlan();
    has skeleton: Skeleton = Skeleton();
    has budget: int = 3;
    has dry_run: bool = False;
    has blocks: dict[str, str] = {};
    has log: list[str] = [];
    has outcome: list[BuildResult] = [];

    # ---- 0/1 · SENSE + PLAN, then lay the mandatory station chain ----
    can begin with Root entry {
        self.log.append("plan");
        self.plan = plan_build(self.task, BACKEND_DECL_GUIDE);
        normalize_plan(self.plan);
        # off-domain plan (the model echoed the guide's example instead of
        # planning THIS task) → one corrective re-plan before anything is built
        drift = plan_fidelity(self.task, self.plan);
        if drift {
            _trace({"station": "plan", "kind": "slot", "slot": "plan_drift", "output": drift});
            try {
                self.plan = plan_build(self.task + "\n\nIMPORTANT: name the endpoints after THIS "
                    + "request's own domain (its nouns and verbs). Do NOT reuse example names "
                    + "like create_note/list_notes.", BACKEND_DECL_GUIDE);
                normalize_plan(self.plan);
            } except Exception {}
        }
        _trace({"station": "plan", "kind": "slot", "slot": "plan_build",
                "input": {"task": self.task}, "output": _plan_dict(self.plan)});
        s1 = here ++> ScaffoldSt();
        s2 = s1 ++> DeclareSt();
        s3 = s2 ++> ImplementSt();
        s4 = s3 ++> VerifySt();
        s4 ++> DoneSt();
        visit s1;
    }

    # ---- 2 · SCAFFOLD (mandatory CODE node — cannot be skipped) ----
    can do_scaffold with ScaffoldSt entry {
        self.log.append("scaffold");
        self.project_dir = os.path.join(self.work_dir, self.plan.name);
        if not self.dry_run {
            res = scaffold_backend(self.work_dir, self.plan.name);
            if (not res.ok) and (not os.path.isdir(self.project_dir)) {
                self.outcome.append(BuildResult(ok=False, stage="scaffold", message=res.errors, files=self.log));
                disengage;
            }
            # the plan is the project's durable, testable contract — mutation
            # graphs (add_endpoint) extend it and regression-exercise it
            _write(self.project_dir, "plan.json", json.dumps(_plan_dict(self.plan), indent=1));
        }
        visit [-->];
    }

    # ---- 3 · DECLARE + DECL-CHECK gate (decls compile ALONE) ----
    can do_declare with DeclareSt entry {
        self.log.append("declare");
        self.skeleton = author_decls(self.plan, BACKEND_DECL_GUIDE);
        force_stub_file(self.skeleton, self.plan);
        write_all(self.project_dir, self.skeleton, self.dry_run);
        res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
        _trace({"station": "declare", "kind": "slot", "slot": "author_decls", "round": 0,
                "input": {"plan": _plan_dict(self.plan)}, "output": render_decls(self.skeleton),
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        mech_n = 0;
        model_failed = False;
        while (not res.ok) and (n < self.budget) {
            # free mechanical repair first (bounded — a non-idempotent corner
            # must never be able to loop); model repair for the rest
            if mech_n < 2 and mechanical_decl_repair(self.skeleton, self.plan, res.errors) {
                mech_n += 1;
                self.log.append("decl-mech-repair");
                force_stub_file(self.skeleton, self.plan);
                write_all(self.project_dir, self.skeleton, self.dry_run);
                res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
                _trace({"station": "declare", "kind": "slot", "slot": "mech_repair", "round": n,
                        "output": render_decls(self.skeleton),
                        "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
                continue;
            }
            self.log.append("decl-repair-" + str(n + 1));
            # a small model can fail to emit a valid Skeleton — catch byLLM's
            # typed-output exception instead of crashing the whole build
            try {
                self.skeleton = repair_decls(render_decls(self.skeleton), res.errors);
            } except Exception as e {
                _trace({"station": "declare", "kind": "slot", "slot": "repair_decls_error",
                        "round": n + 1, "output": str(e)[:300]});
                model_failed = True;
                break;
            }
            force_stub_file(self.skeleton, self.plan);
            write_all(self.project_dir, self.skeleton, self.dry_run);
            res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
            _trace({"station": "declare", "kind": "slot", "slot": "repair_decls", "round": n + 1,
                    "output": render_decls(self.skeleton),
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            msg = res.errors;
            if model_failed {
                msg = "the model couldn't produce a valid declaration for this task — likely "
                    + "too small for it. Try a stronger model: gemma4:e4b "
                    + "(/model ollama_chat/gemma4:e4b) or a hosted model (/model). "
                    + "Last gate errors:\n" + res.errors;
            }
            self.outcome.append(BuildResult(ok=False, stage="decl", message=msg, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 4 · IMPLEMENT (localized fills) + BUILD gate ----
    can do_implement with ImplementSt entry {
        self.log.append("implement");
        for st in self.skeleton.impl_targets {
            self.blocks = fill_impl_blocks(self.skeleton, st, "", self.blocks, "implement", 0, self.project_dir, self.dry_run);
            body = assemble_impl(st, self.blocks);
            update_impl_source(self.skeleton, st.file, body);
            if not self.dry_run {
                _write(self.project_dir, st.file, body);
            }
        }
        res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
        _trace({"station": "implement", "kind": "gate", "gate": "build", "round": 0,
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("build-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                self.blocks = fill_impl_blocks(self.skeleton, st, res.errors, self.blocks, "implement", n + 1, self.project_dir, self.dry_run);
                body = assemble_impl(st, self.blocks);
                update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run {
                    _write(self.project_dir, st.file, body);
                }
            }
            res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
            _trace({"station": "implement", "kind": "gate", "gate": "build", "round": n + 1,
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="build", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 5 · RUNTIME gate: serve + exercise every planned endpoint (the sharp check) ----
    can do_verify with VerifySt entry {
        self.log.append("verify");
        res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
        _trace({"station": "verify", "kind": "gate", "gate": "runtime", "round": 0,
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("runtime-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                self.blocks = fill_impl_blocks(self.skeleton, st, res.errors, self.blocks, "verify", n + 1, self.project_dir, self.dry_run);
                body = assemble_impl(st, self.blocks);
                update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run {
                    _write(self.project_dir, st.file, body);
                }
            }
            # block-assembly is structurally sibling-safe, but re-arm the cheap
            # structural gates before spending a serve cycle
            res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
            if res.ok {
                res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
            }
            _trace({"station": "verify", "kind": "gate", "gate": "runtime", "round": n + 1,
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="runtime", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 6 · DONE ----
    can do_done with DoneSt entry {
        _trace({"station": "done", "kind": "run", "gate_ok": True, "path": self.log});
        self.outcome.append(BuildResult(ok=True, stage="done", message="backend built and verified", files=self.log));
    }
}


"""Load a minicoder-built project from disk into the Skeleton + BuildPlan the
gates operate on (the plan.json contract + the two source files)."""
def load_project(project_dir: str) -> tuple {
    plan = BuildPlan();
    try {
        pd = json.loads(open(os.path.join(project_dir, "plan.json")).read());
        plan.name = pd.get("name", "app");
        plan.summary = pd.get("summary", "");
        plan.endpoints = [
            EndpointSpec(name=e.get("name", ""), example_json=e.get("example_json", "{}"))
            for e in pd.get("endpoints", [])
        ];
    } except Exception {}
    sk = Skeleton();
    for rel in [DECL_FILE, IMPL_FILE] {
        p = os.path.join(project_dir, rel);
        if os.path.exists(p) {
            role = FileRole.IMPL if ".impl." in rel else FileRole.DECL;
            sk.decls.append(DeclFile(path=rel, role=role, source=open(p).read()));
        }
    }
    return (plan, sk);
}

"""Append code-synthesized stubs for signatures that are declared but not yet
implemented — WITHOUT touching existing bodies (the add_endpoint analog of
force_stub_file). Returns the new-signature impl headers, one per line."""
def append_new_stubs(sk: Skeleton) -> str {
    full = synth_stub_impls(sk);
    have: list[str] = [];
    for d in sk.decls {
        if ".impl." not in d.path { continue; }
        for m in re.findall(r"impl\s+(\w+)\.(\w+)\s+with", d.source) {
            have.append(str(m[0]) + "." + str(m[1]));
        }
        for m in re.findall(r"impl\s+(\w+)\s*\(", d.source) {
            have.append(str(m));
        }
    }
    new_lines: list[str] = [];
    new_sigs: list[str] = [];
    for blk in full.split("\n\n") {
        blk = blk.strip();
        if not blk { continue; }
        mm = re.match(r"impl\s+(\w+)(?:\.(\w+))?", blk);
        if mm is None { continue; }
        key = str(mm.group(1)) + ("." + str(mm.group(2)) if mm.group(2) else "");
        if key not in have {
            new_lines.append(blk);
            new_sigs.append(blk.split(" {")[0] + ";");
        }
    }
    if new_lines {
        for d in sk.decls {
            if ".impl." in d.path {
                d.source = d.source.rstrip() + "\n\n" + "\n\n".join(new_lines) + "\n";
            }
        }
    }
    return "\n".join(new_sigs);
}


walker add_endpoint {
    has task: str = "";
    has project_dir: str = "";
    has plan: BuildPlan = BuildPlan();
    has skeleton: Skeleton = Skeleton();
    has new_ep: EndpointSpec = EndpointSpec();
    has budget: int = 3;
    has dry_run: bool = False;
    has blocks: dict[str, str] = {};
    has log: list[str] = [];
    has outcome: list[BuildResult] = [];

    # ---- 0 · SENSE the project + plan the delta ----
    can begin with Root entry {
        self.log.append("plan-add");
        (self.plan, self.skeleton) = load_project(self.project_dir);
        if not self.skeleton.decls {
            self.outcome.append(BuildResult(ok=False, stage="sense",
                message="no minicoder project at " + self.project_dir, files=self.log));
            disengage;
        }
        self.new_ep = plan_add(self.task, render_decls(self.skeleton));
        self.new_ep.example_json = _normalize_example(self.new_ep.example_json);
        _trace({"station": "plan-add", "kind": "slot", "slot": "plan_add",
                "input": {"task": self.task},
                "output": {"name": self.new_ep.name, "example_json": self.new_ep.example_json}});
        self.plan.endpoints.append(self.new_ep);
        s1 = here ++> DeclareSt();
        s2 = s1 ++> ImplementSt();
        s3 = s2 ++> VerifySt();
        s3 ++> DoneSt();
        visit s1;
    }

    # ---- 1 · DECLARE the delta (existing decls stay byte-identical) ----
    can do_declare with DeclareSt entry {
        self.log.append("declare-add");
        addition = "New endpoint: " + self.new_ep.name + " (example call: " + self.new_ep.example_json
            + ") for task: " + self.task + "\n\n" + BACKEND_DECL_GUIDE;
        for d in self.skeleton.decls {
            if ".impl." not in d.path {
                d.source = strip_fences(author_decl_update(d.source, addition));
            }
        }
        new_sigs = append_new_stubs(self.skeleton);
        self.skeleton.impl_targets = [Stub(
            file=IMPL_FILE, signatures=new_sigs,
            intent="Implement the NEW endpoint: " + self.task
        )];
        write_all(self.project_dir, self.skeleton, self.dry_run);
        res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
        _trace({"station": "declare-add", "kind": "slot", "slot": "author_decl_update", "round": 0,
                "output": render_decls(self.skeleton), "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        mech_n = 0;
        while (not res.ok) and (n < self.budget) {
            if mech_n < 2 and mechanical_decl_repair(self.skeleton, self.plan, res.errors) {
                mech_n += 1;
                self.log.append("decl-mech-repair");
                more = append_new_stubs(self.skeleton);
                if more {
                    for st0 in self.skeleton.impl_targets {
                        st0.signatures = (st0.signatures + "\n" + more).strip();
                    }
                }
                write_all(self.project_dir, self.skeleton, self.dry_run);
                res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
                _trace({"station": "declare-add", "kind": "slot", "slot": "mech_repair", "round": n,
                        "output": render_decls(self.skeleton), "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
                continue;
            }
            self.log.append("decl-repair-" + str(n + 1));
            self.skeleton = repair_decls(render_decls(self.skeleton), res.errors);
            more = append_new_stubs(self.skeleton);
            if more {
                for st0 in self.skeleton.impl_targets {
                    st0.signatures = (st0.signatures + "\n" + more).strip();
                }
            }
            write_all(self.project_dir, self.skeleton, self.dry_run);
            res = decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
            _trace({"station": "declare-add", "kind": "slot", "slot": "repair_decls", "round": n + 1,
                    "output": render_decls(self.skeleton), "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="decl", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 2 · IMPLEMENT only the new stubs ----
    can do_implement with ImplementSt entry {
        self.log.append("implement-add");
        for st in self.skeleton.impl_targets {
            if not st.signatures {
                # idempotent re-add / prior failed attempt: take leverage over
                # every existing block instead of doing nothing
                st.signatures = all_impl_sigs(self.skeleton);
            }
            if not st.signatures { continue; }
            cur0 = "";
            for d0 in self.skeleton.decls {
                if d0.path == st.file { cur0 = d0.source; }
            }
            self.blocks = fill_impl_blocks(self.skeleton, st, "", self.blocks, "implement-add", 0, self.project_dir, self.dry_run, cur0);
            cur = "";
            for d in self.skeleton.decls {
                if d.path == st.file { cur = d.source; }
            }
            body = merge_impl_blocks(cur, self.blocks);
            update_impl_source(self.skeleton, st.file, body);
            if not self.dry_run {
                _write(self.project_dir, st.file, body);
            }
        }
        res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
        _trace({"station": "implement-add", "kind": "gate", "gate": "build", "round": 0,
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("build-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                if not st.signatures { continue; }
                cur0 = "";
                for d0 in self.skeleton.decls {
                    if d0.path == st.file { cur0 = d0.source; }
                }
                self.blocks = fill_impl_blocks(self.skeleton, st, res.errors, self.blocks, "implement-add", n + 1, self.project_dir, self.dry_run, cur0);
                cur = "";
                for d in self.skeleton.decls {
                    if d.path == st.file { cur = d.source; }
                }
                body = merge_impl_blocks(cur, self.blocks);
                update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run {
                    _write(self.project_dir, st.file, body);
                }
            }
            res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
            _trace({"station": "implement-add", "kind": "gate", "gate": "build", "round": n + 1,
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="build", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 3 · VERIFY: regression-exercise ALL endpoints (old + new) ----
    can do_verify with VerifySt entry {
        self.log.append("verify-add");
        res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
        _trace({"station": "verify-add", "kind": "gate", "gate": "runtime", "round": 0,
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("runtime-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                if not st.signatures { continue; }
                cur0 = "";
                for d0 in self.skeleton.decls {
                    if d0.path == st.file { cur0 = d0.source; }
                }
                self.blocks = fill_impl_blocks(self.skeleton, st, res.errors, self.blocks, "verify-add", n + 1, self.project_dir, self.dry_run, cur0);
                cur = "";
                for d in self.skeleton.decls {
                    if d.path == st.file { cur = d.source; }
                }
                body = merge_impl_blocks(cur, self.blocks);
                update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run {
                    _write(self.project_dir, st.file, body);
                }
            }
            res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
            if res.ok {
                res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
            }
            _trace({"station": "verify-add", "kind": "gate", "gate": "runtime", "round": n + 1,
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="runtime", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # ---- 4 · DONE: persist the extended contract ----
    can do_done with DoneSt entry {
        if not self.dry_run {
            _write(self.project_dir, "plan.json", json.dumps(_plan_dict(self.plan), indent=1));
        }
        _trace({"station": "done", "kind": "run", "gate_ok": True, "path": self.log});
        self.outcome.append(BuildResult(ok=True, stage="done",
            message="endpoint added and all endpoints re-verified", files=self.log));
    }
}


walker fix_bug {
    has task: str = "";
    has project_dir: str = "";
    has plan: BuildPlan = BuildPlan();
    has skeleton: Skeleton = Skeleton();
    has budget: int = 3;
    has dry_run: bool = False;
    has blocks: dict[str, str] = {};
    has log: list[str] = [];
    has outcome: list[BuildResult] = [];

    # ---- 0 · SENSE the project; seed blocks from the real bodies ----
    can begin with Root entry {
        self.log.append("sense-bug");
        (self.plan, self.skeleton) = load_project(self.project_dir);
        if not self.skeleton.decls {
            self.outcome.append(BuildResult(ok=False, stage="sense",
                message="no minicoder project at " + self.project_dir, files=self.log));
            disengage;
        }
        sigs: list[str] = [];
        for d in self.skeleton.decls {
            if ".impl." not in d.path { continue; }
            for seg0 in re.split(r"(?m)^(?=impl\s)", d.source) {
                seg = str(seg0).strip();
                if not seg { continue; }
                self.blocks[block_key(seg)] = seg;
                sigs.append(seg.split("{")[0].strip().rstrip(";") + ";");
            }
        }
        self.skeleton.impl_targets = [Stub(
            file=IMPL_FILE, signatures="\n".join(sigs),
            intent="FIX THIS BUG (change only what the bug requires): " + self.task
        )];
        s1 = here ++> VerifySt();
        s1 ++> DoneSt();
        visit s1;
    }

    # ---- 1 · REPRODUCE via the gate ladder, then per-block repair ----
    can do_fix with VerifySt entry {
        self.log.append("reproduce");
        res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
        if res.ok {
            res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
        }
        _trace({"station": "fix", "kind": "gate", "gate": "reproduce", "round": 0,
                "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        if res.ok {
            # gates are the harness's definition of correct — say so honestly
            self.outcome.append(BuildResult(ok=True, stage="no-repro",
                message="all gates green — bug not reproducible by the harness gates; nothing changed",
                files=self.log));
            disengage;
        }
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("fix-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                cur = "";
                for d in self.skeleton.decls {
                    if d.path == st.file { cur = d.source; }
                }
                self.blocks = fill_impl_blocks(self.skeleton, st, res.errors, self.blocks,
                                               "fix", n + 1, self.project_dir, self.dry_run, cur);
                body = merge_impl_blocks(cur, self.blocks);
                update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run {
                    _write(self.project_dir, st.file, body);
                }
            }
            res = impl_gates(self.project_dir, self.skeleton, self.dry_run);
            if res.ok {
                res = gate_serve(self.project_dir, self.plan.endpoints, self.dry_run);
            }
            _trace({"station": "fix", "kind": "gate", "gate": "runtime", "round": n + 1,
                    "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(BuildResult(ok=False, stage="runtime", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    can do_done with DoneSt entry {
        _trace({"station": "done", "kind": "run", "gate_ok": True, "path": self.log});
        self.outcome.append(BuildResult(ok=True, stage="done",
            message="bug fixed; all endpoints re-verified live", files=self.log));
    }
}


"""Spawn the build_backend task-graph on root and return its single result."""
def smith(task: str, work_dir: str, dry_run: bool = False) -> BuildResult {
    w = root spawn build_backend(task=task, work_dir=work_dir, dry_run=dry_run);
    return w.outcome[0] if w.outcome else BuildResult(ok=False, stage="none", message="no report");
}

"""Spawn the add_endpoint task-graph against an existing project."""
def smith_add(task: str, project_dir: str, dry_run: bool = False) -> BuildResult {
    w = root spawn add_endpoint(task=task, project_dir=project_dir, dry_run=dry_run);
    return w.outcome[0] if w.outcome else BuildResult(ok=False, stage="none", message="no report");
}

"""Spawn the fix_bug task-graph against an existing project."""
def smith_fix(task: str, project_dir: str, dry_run: bool = False) -> BuildResult {
    w = root spawn fix_bug(task=task, project_dir=project_dir, dry_run=dry_run);
    return w.outcome[0] if w.outcome else BuildResult(ok=False, stage="none", message="no report");
}

glob FIX_WORDS: list[str] = ["fix", "bug", "broken", "wrong", "crash", "error", "fails", "doesn't", "does not"];

"""The task router (owner=code — P1): a bare workspace means build; an existing
project means a mutation graph, discriminated by the task's own vocabulary.
A GEN-ENUM route slot enters only when the graph library outgrows this."""
def route(work_dir: str, task: str = "") -> str {
    proj = "";
    if os.path.exists(os.path.join(work_dir, DECL_FILE)) {
        proj = work_dir;
    } else {
        for child in (os.listdir(work_dir) if os.path.isdir(work_dir) else []) {
            if os.path.exists(os.path.join(work_dir, child, DECL_FILE)) {
                proj = os.path.join(work_dir, child);
                break;
            }
        }
    }
    if not proj { return "build_backend"; }
    lowered = task.lower();
    if any([w in lowered for w in FIX_WORDS]) {
        return "fix_bug:" + proj;
    }
    return "add_endpoint:" + proj;
}


# ==========================================================================
# NODE-RESIDENT KNOWLEDGE — scoped Jac best practices, bound to the stations
# by CODE (not a tool the model may forget to call).
# ==========================================================================

glob BACKEND_DECL_GUIDE: str =
"JAC BACKEND — DECL SURFACE (write signatures, not statement bodies).\n"
"A backend is a graph of node/edge archetypes + walkers that traverse it. REST endpoints are `walker:pub <name>`.\n"
"The project is already scaffolded with entry-point main.sv.jac. Author EXACTLY ONE file:\n"
"  main.sv.jac — ALL declarations: docstring, node/edge archetypes, walker:pub endpoints, def signatures.\n"
"(Walkers MUST live in main.sv.jac itself — walkers imported from another module are NOT served.\n"
" Do NOT write any impl file — stub bodies are generated automatically from your signatures.)\n"
"\n"
"The example below is SYNTAX ONLY. `Note`/`create_note`/`list_notes` are placeholders —\n"
"name every node, walker and field after the USER'S OWN domain (a tweet app declares\n"
"`node Tweet` and `walker:pub post_tweet`, NOT `Note`/`create_note`). Copying these\n"
"placeholder names is the single most common mistake.\n"
"\n"
"main.sv.jac (DECLARATIONS ONLY — no statement bodies):\n"
"  node Note { has title: str; has body: str = \"\"; }    # typed has, defaults; NEVER `T | None` on a node — use \"\"/0 sentinel\n"
"  walker:pub create_note {\n"
"      has title: str;\n"
"      has body: str = \"\";\n"
"      has reports: list[Note] = [];      # typed report channel — declare it, write it ONLY via `report`\n"
"      can run with Root entry;           # ability SIGNATURE only — no body here\n"
"  }\n"
"Declare ONLY what the task needs — no helper functions the task did not ask for.\n"
"\n"
"A walker that LISTS nodes needs TWO abilities — one to traverse, one to collect:\n"
"  walker:pub list_notes { has reports: list[Note] = []; can run with Root entry; can collect with Note entry; }\n"
"\n"
"Rules (distilled from the Jac language skills — each is a real compile/runtime trap):\n"
"- `has` field ORDER: fields with defaults must come AFTER fields without (`has title: str; has body: str = \"\";` — never the reverse).\n"
"- NEVER `T | None` on a node field — use a \"\"/0 sentinel default instead.\n"
"- every `can`/`def` line is a SIGNATURE ending in `;` — no bodies anywhere in this file.\n"
"- `has reports: list[T] = [];` — the `= []` default is REQUIRED (omitting it makes reports a required API parameter).\n"
"- entry abilities are `can`, never `def`; a `def` is a plain function.\n"
"- relationships between nodes are `edge Rel { has since: str = \"\"; }` archetypes.\n"
"- `Root` (capitalized) in `with ... entry` annotations; no `global` keyword; plain code only (no `by llm`).\n"
"Emit exactly ONE DeclFile (main.sv.jac). impl_targets may be left empty — it is derived from your signatures.";


glob BACKEND_IMPL_GUIDE: str =
"JAC BACKEND — IMPL BODY (fill ONE *.impl.jac).\n"
"Output only the `impl ...` block(s) for this file — no archetype redeclarations, no prose, no markdown fences.\n"
"Inside a walker ability `impl W.ability with NodeType entry { ... }`: `self`=walker, `here`=current node.\n"
"  create+return: `report here ++> Note(title=self.title, body=self.body);`\n"
"  traverse:      `visit [-->];` (outgoing) — then a second `impl W.other with Note entry { report here; }` collects\n"
"  filter:        `[here -->][?:Note][?title == self.title]`  (count: `len([here -->][?:Note])`)\n"
"  get-or-create: `visit [here-->[?:Note, title==self.title]] else { fresh = here ++> Note(title=self.title); visit fresh; }`\n"
"  delete:        `for n in [here -->][?:Note][?title == self.title] { del n; }`\n"
"  update:        assign node fields directly in the collector: `here.body = self.body;`\n"
"  return:        values leave ONLY via `report X;` — NEVER assign or append to `reports` yourself.\n"
"Traversal control (distilled — each is a real trap): `visit` is a STATEMENT, never `self.visit(...)`;\n"
"`disengage;` halts the walker AND DISCARDS queued visits — never place it right after `visit` (the visits die);\n"
"`skip;` ends only the current ability; `here`=current node, `self`=the walker (mixing them is the #1 bug).\n"
"The walker's `has` fields carry the CALLER'S input — use them exactly as passed; NEVER overwrite them with hardcoded/demo values.\n"
"Jac is a PYTHON superset, not JavaScript: no `let`/`const`/`=>`; string/list methods are Python's (.lower(), .strip(), .replace(), .append()).\n"
"Implement only the signatures named for this file; keep everything else unchanged.";
