"""fullstack — frontend templates, style judgment, and browser gates.

The frontend of a standard CRUD app is code-derived the same way the backend
is: the form comes from the write endpoint's payload fields, the list from the
read endpoint, the styling from a designed token sheet with a deterministic
accent. The model contributes exactly two things: the page's WORDS (a typed
UiCopy fill, written under a style-judgment sem) and — after the browser gate
has clicked through the real app — a CSS-only refinement pass driven by a
VISION verdict (the local model looks at the screenshot).
"""

import os;
import re;
import json;
import time;
import subprocess;
import jacsmith;
import from jaclang.byllm.lib { Model, Image }

glob JAC: str = os.path.expanduser("~/.local/bin/jac");

glob STYLE_JUDGMENT: str =
"You are judging/writing UI with real design standards. A NICE page has: one clear "
"visual hierarchy (a strong title, quieter supporting text); an 8px spacing rhythm; "
"ONE accent color used sparingly on primary actions, calm hue-tinted neutrals "
"elsewhere (never rainbow); readable text (16px+ body, line-height 1.5, max 65ch); "
"visible states (hover, focus ring, and a designed empty state — never a blank "
"void); real specific copy (no lorem, no 'Welcome to my app'); restraint (no "
"gradient soup, no emoji as decoration). Penalize: default-browser look, "
"overlapping or clipped elements, invisible text, cramped forms, clashing colors.";

glob ACCENTS: list[str] = ["#4f46e5", "#0e7490", "#b45309", "#be185d", "#15803d"];

def accent_for(name: str) -> str {
    h = 0;
    for c in name { h = (h * 31 + ord(c)) % 997; }
    return ACCENTS[h % len(ACCENTS)];
}


obj UiCopy {
    has title: str = "";
    has tagline: str = "";
    has empty_state: str = "";
    has submit_label: str = "";
}
sem UiCopy = "The page's written words. Specific beats clever; sentence case; no lorem; no exclamation marks.";
sem UiCopy.title = "Short product-style name for this app (2-4 words, title case).";
sem UiCopy.tagline = "One quiet sentence saying what the page does.";
sem UiCopy.empty_state = "One friendly sentence shown when the list is empty, inviting the first entry.";
sem UiCopy.submit_label = "1-2 word verb label for the submit button (e.g. 'Add note').";

def style_copy(brief: str, guide: str) -> UiCopy by llm(temperature=0.2);
sem style_copy = "Write the UI copy for this app.";
sem style_copy.brief = "What the app does and its endpoints.";
sem style_copy.guide = "The design standards to follow.";


obj UiVerdict {
    has renders: bool = False;
    has quality: int = 0;
    has issues: list[str] = [];
}
sem UiVerdict = "A design verdict on a rendered page screenshot.";
sem UiVerdict.renders = "True if the page shows a styled, working app UI (not a blank page, error text, or raw JSON).";
sem UiVerdict.quality = "1-5 against the design standards: 5 = genuinely nice; 3 = acceptable; 1 = broken or default-browser ugly.";
sem UiVerdict.issues = "Up to 3 concrete visual problems, each fixable in CSS (e.g. 'inputs cramped — increase gap and padding').";

def judge_ui(img: Image, guide: str) -> UiVerdict by llm(temperature=0.1);
sem judge_ui = "Look at this screenshot of a web app and judge it against the design standards.";
sem judge_ui.img = "The rendered page screenshot.";
sem judge_ui.guide = "The design standards.";

def restyle_css(current: str, issues: str) -> str by llm(temperature=0.2);
sem restyle_css = "Rewrite this stylesheet to fix the listed visual issues. Keep EVERY selector name unchanged. Output ONLY the complete CSS file — no prose, no markdown fences.";
sem restyle_css.current = "The current CSS.";
sem restyle_css.issues = "The visual issues to fix, plus the design standards.";


# ---- template derivation (owner=code) --------------------------------------

def plan_fields(plan: jacsmith.BuildPlan) -> list[str] {
    out: list[str] = [];
    for e in plan.endpoints {
        if jacsmith._is_read_endpoint(e.name) { continue; }
        try {
            pd = json.loads(e.example_json);
            for k in pd.keys() {
                if k != "reports" and str(k) not in out { out.append(str(k)); }
            }
        } except Exception {}
    }
    return out;
}

def write_walker_name(plan: jacsmith.BuildPlan) -> str {
    for e in plan.endpoints {
        if not jacsmith._is_read_endpoint(e.name) { return e.name; }
    }
    return "";
}

def list_walker_name(plan: jacsmith.BuildPlan) -> str {
    for e in plan.endpoints {
        if jacsmith._is_read_endpoint(e.name) and (not jacsmith._is_agg_endpoint(e.name)) {
            return e.name;
        }
    }
    return "";
}

glob NL: str = chr(10);
glob DQ: str = chr(34);

def render_style_css(accent: str) -> str {
    lines = [
        ":root { --accent: " + accent + "; --bg: #f7f7f5; --card: #ffffff; --ink: #23262e;",
        "        --muted: #6b7078; --line: #e4e3df; --radius: 10px; }",
        "* { box-sizing: border-box; }",
        "body { margin: 0; background: var(--bg); color: var(--ink);",
        "       font: 16px/1.5 system-ui, -apple-system, sans-serif; }",
        ".shell { max-width: 640px; margin: 0 auto; padding: 48px 20px 80px; }",
        ".head h1 { margin: 0 0 4px; font-size: 28px; font-weight: 700; letter-spacing: -0.01em; }",
        ".head .tagline { margin: 0 0 28px; color: var(--muted); }",
        ".entry-form { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 24px; }",
        ".entry-form input { flex: 1 1 140px; padding: 10px 12px; font-size: 15px;",
        "  border: 1px solid var(--line); border-radius: var(--radius); background: var(--card); }",
        ".entry-form input:focus { outline: 2px solid var(--accent); outline-offset: 1px; border-color: var(--accent); }",
        ".entry-form button { padding: 10px 18px; font-size: 15px; font-weight: 600; color: #fff;",
        "  background: var(--accent); border: none; border-radius: var(--radius); cursor: pointer; }",
        ".entry-form button:hover { filter: brightness(1.08); }",
        ".card-list { display: flex; flex-direction: column; gap: 10px; }",
        ".card { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);",
        "  padding: 14px 16px; display: flex; flex-direction: column; gap: 2px; }",
        ".card strong { font-size: 15.5px; }",
        ".card span { color: var(--muted); font-size: 14px; }",
        ".empty { border: 1.5px dashed var(--line); border-radius: var(--radius); padding: 32px 16px;",
        "  text-align: center; color: var(--muted); }"
    ];
    return NL.join(lines) + NL;
}

"""Collapse a stylesheet to a single safe Jac string literal (the <style> tag
route — bundler-independent delivery)."""
def css_one_line(css: str) -> str {
    s = css.replace(DQ, "'");
    s = re.sub(r"\s+", " ", s);
    return s.strip();
}

def render_frontend_cl(plan: jacsmith.BuildPlan, copy: UiCopy) -> str {
    fields = plan_fields(plan);
    node_t = jacsmith._derive_node_name(plan);
    wname = write_walker_name(plan);
    lname = list_walker_name(plan);
    q = DQ;
    L: list[str] = [];
    L.append(q + q + q + copy.title + " — client UI." + q + q + q);
    L.append("");
    L.append("sv import from endpoints { " + node_t + ", " + wname + ", " + lname + " }");
    L.append("");
    L.append("glob PAGE_CSS: str = " + q + css_one_line(render_style_css(accent_for(plan.name))) + q + ";");
    L.append("");
    L.append("def:pub app -> JsxElement {");
    L.append("    has items: list[" + node_t + "] = [];");
    for f in fields { L.append("    has " + f + ": str = " + q + q + ";"); }
    L.append("");
    L.append("    can with entry {");
    L.append("        loadItems();");
    L.append("    }");
    L.append("");
    L.append("    async def loadItems -> None;");
    L.append("    async def submitItem(e: FormEvent) -> None;");
    L.append("");
    L.append("    return <div className=" + q + "shell" + q + ">");
    L.append("        <style>{PAGE_CSS}</style>");
    L.append("        <header className=" + q + "head" + q + ">");
    L.append("            <h1>" + copy.title + "</h1>");
    L.append("            <p className=" + q + "tagline" + q + ">" + copy.tagline + "</p>");
    L.append("        </header>");
    L.append("        <form className=" + q + "entry-form" + q + " onSubmit={submitItem}>");
    for f in fields {
        ph = f[0].upper() + f[1:];
        L.append("            <input id=" + q + "f-" + f + q + " type=" + q + "text" + q + " value={" + f + "}");
        L.append("                onChange={lambda (e: ChangeEvent) { " + f + " = e.target.value; }}");
        L.append("                placeholder=" + q + ph + q + " />");
    }
    L.append("            <button id=" + q + "f-submit" + q + " type=" + q + "submit" + q + ">" + copy.submit_label + "</button>");
    L.append("        </form>");
    L.append("        <section className=" + q + "card-list" + q + ">");
    L.append("            {if len(items) == 0 {");
    L.append("                <p className=" + q + "empty" + q + ">" + copy.empty_state + "</p>");
    L.append("                skip;");
    L.append("            }}");
    L.append("            {for (i, it) in enumerate(items) {");
    card = "<strong>{it." + fields[0] + "}</strong>" if fields else "<strong>item</strong>";
    for f in fields[1:] { card = card + "<span>{it." + f + "}</span>"; }
    L.append("                <article key={str(i)} className=" + q + "card" + q + ">" + card + "</article>");
    L.append("            }}");
    L.append("        </section>");
    L.append("    </div>;");
    L.append("}");
    return NL.join(L) + NL;
}

def render_frontend_impl(plan: jacsmith.BuildPlan) -> str {
    fields = plan_fields(plan);
    wname = write_walker_name(plan);
    lname = list_walker_name(plan);
    q = DQ;
    kwargs = ", ".join([f + "=" + f for f in fields]);
    L: list[str] = [];
    L.append(q + q + q + "Frontend handler implementations." + q + q + q);
    L.append("");
    L.append("impl app.loadItems -> None {");
    L.append("    result = root spawn " + lname + "();");
    L.append("    items = result.reports;");
    L.append("}");
    L.append("");
    L.append("impl app.submitItem(e: FormEvent) -> None {");
    L.append("    e.preventDefault();");
    L.append("    result = root spawn " + wname + "(" + kwargs + ");");
    L.append("    if result.reports and len(result.reports) > 0 {");
    L.append("        items = items + [result.reports[0]];");
    L.append("    }");
    for f in fields { L.append("    " + f + " = " + q + q + ";"); }
    L.append("}");
    return NL.join(L) + NL;
}

def render_main_entry(plan: jacsmith.BuildPlan, copy: UiCopy) -> str {
    node_t = jacsmith._derive_node_name(plan);
    q = DQ;
    wnames = ", ".join([e.name for e in plan.endpoints]);
    L: list[str] = [];
    L.append(q + q + q + copy.title + " — entry point." + q + q + q);
    L.append("");
    L.append("import from endpoints { " + node_t + ", " + wnames + " }");
    L.append("");
    L.append("cl {");
    L.append("    import from .frontend { app as ClientApp }");
    L.append("");
    L.append("    def:pub app -> JsxElement {");
    L.append("        return <ClientApp/>;");
    L.append("    }");
    L.append("}");
    return NL.join(L) + NL;
}


# ---- the click-through browser gate (owner=code) ---------------------------

def _browse(args: list[str], cwd: str) -> str {
    r = subprocess.run([JAC, "browse"] + args, cwd=cwd, capture_output=True, text=True, timeout=120);
    return (r.stdout or "") + (r.stderr or "");
}

"""Drive the real rendered app: open, FILL the form with the plan's example
payload via the template's stable ids, CLICK submit, assert the written value
appears in the page, then screenshot the populated page for the vision judge."""
def gate_ui(project_dir: str, plan: jacsmith.BuildPlan, shot_path: str, dry: bool) -> jacsmith.CheckResult {
    if dry { return jacsmith.CheckResult(ok=True, errors=""); }
    base = "http://localhost:" + str(jacsmith.SERVE_PORT);
    fields = plan_fields(plan);
    wname = write_walker_name(plan);
    example: dict = {};
    for e in plan.endpoints {
        if e.name == wname {
            try { example = json.loads(e.example_json); } except Exception {}
        }
    }
    try {
        _browse(["open", base], project_dir);
        w = _browse(["wait", "#f-submit"], project_dir);
        if ("error" in w.lower()) and ("time" in w.lower()) {
            _browse(["close"], project_dir);
            return jacsmith.CheckResult(ok=False,
                errors="UI: the form never became actionable — page blank or crashed: " + w[:300]);
        }
        for f in fields {
            val = str(example.get(f, "example"));
            _browse(["fill", "#f-" + f, val], project_dir);
        }
        _browse(["click", "#f-submit"], project_dir);
        time.sleep(1.5);
        snap = _browse(["snapshot"], project_dir);
        _browse(["screenshot", shot_path], project_dir);
        _browse(["close"], project_dir);
        probe = str(example.get(fields[0], "")) if fields else "";
        if probe and (probe not in snap) {
            return jacsmith.CheckResult(ok=False,
                errors="UI: filled and clicked the form but '" + probe
                    + "' never appeared in the page — the UI write/read loop is broken.");
        }
        return jacsmith.CheckResult(ok=True, errors="");
    } except Exception as ex {
        try { _browse(["close"], project_dir); } except Exception {}
        return jacsmith.CheckResult(ok=False, errors="UI: browser exercise failed: " + str(ex)[:300]);
    }
}


# ---- the build_fullstack task-graph ----------------------------------------

walker build_fullstack {
    has task: str = "";
    has work_dir: str = "";
    has project_dir: str = "";
    has plan: jacsmith.BuildPlan = jacsmith.BuildPlan();
    has skeleton: jacsmith.Skeleton = jacsmith.Skeleton();
    has copy: UiCopy = UiCopy();
    has budget: int = 3;
    has dry_run: bool = False;
    has blocks: dict[str, str] = {};
    has log: list[str] = [];
    has outcome: list[jacsmith.BuildResult] = [];

    can begin with Root entry {
        self.log.append("plan");
        jacsmith.DECL_FILE = "endpoints.sv.jac";
        jacsmith.IMPL_FILE = "endpoints.sv.impl.jac";
        jacsmith.ENTRY_FILE = "main.jac";
        self.plan = jacsmith.plan_build(self.task, jacsmith.BACKEND_DECL_GUIDE);
        jacsmith._trace({"station": "plan", "kind": "slot", "slot": "plan_build",
                         "input": {"task": self.task}, "output": jacsmith._plan_dict(self.plan)});
        brief = self.plan.summary + " Endpoints: " + ", ".join([e.name for e in self.plan.endpoints]);
        try {
            self.copy = style_copy(brief, STYLE_JUDGMENT);
        } except Exception {
            self.copy = UiCopy(title=self.plan.name, tagline=self.plan.summary,
                               empty_state="Nothing here yet — add the first one.",
                               submit_label="Add");
        }
        if not self.copy.title { self.copy.title = self.plan.name; }
        if not self.copy.submit_label { self.copy.submit_label = "Add"; }
        jacsmith._trace({"station": "plan", "kind": "slot", "slot": "style_copy",
                         "output": {"title": self.copy.title, "tagline": self.copy.tagline}});
        s1 = here ++> jacsmith.ScaffoldSt();
        s2 = s1 ++> jacsmith.DeclareSt();
        s3 = s2 ++> jacsmith.ImplementSt();
        s4 = s3 ++> jacsmith.VerifySt();
        s4 ++> jacsmith.DoneSt();
        visit s1;
    }

    # scaffold web-app + write the code-derived frontend (entry, page, impl, css)
    can do_scaffold with jacsmith.ScaffoldSt entry {
        self.log.append("scaffold");
        self.project_dir = os.path.join(self.work_dir, self.plan.name);
        if not self.dry_run {
            r = subprocess.run([JAC, "create", self.plan.name, "--kind", "web-app", "--force"],
                               cwd=self.work_dir, capture_output=True, text=True);
            if (r.returncode != 0) and (not os.path.isdir(self.project_dir)) {
                self.outcome.append(jacsmith.BuildResult(ok=False, stage="scaffold",
                    message=(r.stdout or "") + (r.stderr or ""), files=self.log));
                disengage;
            }
            jacsmith._write(self.project_dir, "plan.json",
                            json.dumps(jacsmith._plan_dict(self.plan), indent=1));
            jacsmith._write(self.project_dir, "main.jac", render_main_entry(self.plan, self.copy));
            jacsmith._write(self.project_dir, "frontend.cl.jac", render_frontend_cl(self.plan, self.copy));
            jacsmith._write(self.project_dir, "frontend.impl.jac", render_frontend_impl(self.plan));
            jacsmith._write(self.project_dir, "frontend.css",
                            render_style_css(accent_for(self.plan.name)));
            mc = os.path.join(self.project_dir, "components", "MessageCard.cl.jac");
            if os.path.exists(mc) { os.remove(mc); }
        }
        visit [-->];
    }

    can do_declare with jacsmith.DeclareSt entry {
        self.log.append("declare");
        self.skeleton = jacsmith.author_decls(self.plan, jacsmith.BACKEND_DECL_GUIDE);
        jacsmith.force_stub_file(self.skeleton, self.plan);
        jacsmith.write_all(self.project_dir, self.skeleton, self.dry_run);
        res = jacsmith.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
        jacsmith._trace({"station": "declare", "kind": "slot", "slot": "author_decls", "round": 0,
                         "output": jacsmith.render_decls(self.skeleton),
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        mech_n = 0;
        while (not res.ok) and (n < self.budget) {
            if mech_n < 2 and jacsmith.mechanical_decl_repair(self.skeleton, self.plan, res.errors) {
                mech_n += 1;
                self.log.append("decl-mech-repair");
                jacsmith.force_stub_file(self.skeleton, self.plan);
                jacsmith.write_all(self.project_dir, self.skeleton, self.dry_run);
                res = jacsmith.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
                jacsmith._trace({"station": "declare", "kind": "slot", "slot": "mech_repair", "round": n,
                                 "output": jacsmith.render_decls(self.skeleton),
                                 "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
                continue;
            }
            self.log.append("decl-repair-" + str(n + 1));
            self.skeleton = jacsmith.repair_decls(jacsmith.render_decls(self.skeleton), res.errors);
            jacsmith.force_stub_file(self.skeleton, self.plan);
            jacsmith.write_all(self.project_dir, self.skeleton, self.dry_run);
            res = jacsmith.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
            jacsmith._trace({"station": "declare", "kind": "slot", "slot": "repair_decls", "round": n + 1,
                             "output": jacsmith.render_decls(self.skeleton),
                             "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(jacsmith.BuildResult(ok=False, stage="decl", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    can do_implement with jacsmith.ImplementSt entry {
        self.log.append("implement");
        for st in self.skeleton.impl_targets {
            self.blocks = jacsmith.fill_impl_blocks(self.skeleton, st, "", self.blocks,
                                                    "implement", 0, self.project_dir, self.dry_run);
            body = jacsmith.assemble_impl(st, self.blocks);
            jacsmith.update_impl_source(self.skeleton, st.file, body);
            if not self.dry_run { jacsmith._write(self.project_dir, st.file, body); }
        }
        res = jacsmith.impl_gates(self.project_dir, self.skeleton, self.dry_run);
        jacsmith._trace({"station": "implement", "kind": "gate", "gate": "build", "round": 0,
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("build-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                self.blocks = jacsmith.fill_impl_blocks(self.skeleton, st, res.errors, self.blocks,
                                                        "implement", n + 1, self.project_dir, self.dry_run);
                body = jacsmith.assemble_impl(st, self.blocks);
                jacsmith.update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run { jacsmith._write(self.project_dir, st.file, body); }
            }
            res = jacsmith.impl_gates(self.project_dir, self.skeleton, self.dry_run);
            jacsmith._trace({"station": "implement", "kind": "gate", "gate": "build", "round": n + 1,
                             "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(jacsmith.BuildResult(ok=False, stage="build", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # serve (REST regression) → click-through browser gate → vision verdict →
    # bounded CSS-only refine round ("the switcharoo")
    can do_verify with jacsmith.VerifySt entry {
        self.log.append("verify");
        res = jacsmith.gate_serve(self.project_dir, self.plan.endpoints, self.dry_run, 240);
        jacsmith._trace({"station": "verify", "kind": "gate", "gate": "runtime", "round": 0,
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        if not res.ok {
            self.outcome.append(jacsmith.BuildResult(ok=False, stage="runtime", message=res.errors, files=self.log));
            disengage;
        }
        if not self.dry_run {
            shot = os.path.join(self.project_dir, "ui_shot.png");
            # keep the server alive for the browser: gate_serve terminated it,
            # so start it again for the UI leg
            srv = subprocess.Popen([JAC, "start", "main.jac", "--port", str(jacsmith.SERVE_PORT)],
                                   cwd=self.project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
            try {
                time.sleep(8);
                ui = gate_ui(self.project_dir, self.plan, shot, self.dry_run);
                jacsmith._trace({"station": "verify", "kind": "gate", "gate": "ui", "round": 0,
                                 "gate_ok": ui.ok, "gate_errors": ui.errors[:2000]});
                if not ui.ok {
                    self.outcome.append(jacsmith.BuildResult(ok=False, stage="ui", message=ui.errors, files=self.log));
                    disengage;
                }
                if os.path.exists(shot) {
                    try {
                        verdict = judge_ui(Image(shot), STYLE_JUDGMENT);
                        jacsmith._trace({"station": "verify", "kind": "slot", "slot": "judge_ui",
                                         "output": {"renders": verdict.renders, "quality": verdict.quality,
                                                    "issues": verdict.issues}});
                        if verdict.issues and verdict.quality < 4 {
                            self.log.append("restyle");
                            css_path = os.path.join(self.project_dir, "frontend.css");
                            cur = open(css_path).read();
                            newcss = jacsmith.strip_fences(restyle_css(
                                cur, "\n".join(verdict.issues) + "\n\n" + STYLE_JUDGMENT));
                            if newcss and (":root" in newcss or "." in newcss) {
                                jacsmith._write(self.project_dir, "frontend.css", newcss);
                                clp = os.path.join(self.project_dir, "frontend.cl.jac");
                                cl_src = open(clp).read();
                                cl_new = re.sub(r"glob PAGE_CSS: str = \".*\";",
                                    "glob PAGE_CSS: str = " + json.dumps(css_one_line(newcss)) + ";",
                                    cl_src, count=1);
                                jacsmith._write(self.project_dir, "frontend.cl.jac", cl_new);
                                chk = jacsmith.gate_check(self.project_dir, self.dry_run);
                                if not chk.ok {
                                    jacsmith._write(self.project_dir, "frontend.cl.jac", cl_src);
                                    jacsmith._write(self.project_dir, "frontend.css", cur);
                                } else {
                                    jacsmith._trace({"station": "verify", "kind": "slot", "slot": "restyle_css",
                                                     "output": newcss[:1500]});
                                    # fresh server so the rebuilt client ships the new styles
                                    srv.terminate();
                                    time.sleep(1);
                                    srv = subprocess.Popen([JAC, "start", "main.jac", "--port", str(jacsmith.SERVE_PORT)],
                                                           cwd=self.project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
                                    time.sleep(12);
                                    ui2 = gate_ui(self.project_dir, self.plan, shot, self.dry_run);
                                    jacsmith._trace({"station": "verify", "kind": "gate", "gate": "ui", "round": 1,
                                                     "gate_ok": ui2.ok, "gate_errors": ui2.errors[:1000]});
                                    if not ui2.ok {
                                        jacsmith._write(self.project_dir, "frontend.cl.jac", cl_src);
                                        jacsmith._write(self.project_dir, "frontend.css", cur);
                                    }
                                }
                            }
                        }
                    } except Exception {}
                }
            } finally {
                srv.terminate();
            }
        }
        visit [-->];
    }

    can do_done with jacsmith.DoneSt entry {
        jacsmith.DECL_FILE = "main.sv.jac";
        jacsmith.IMPL_FILE = "main.sv.impl.jac";
        jacsmith.ENTRY_FILE = "main.sv.jac";
        jacsmith._trace({"station": "done", "kind": "run", "gate_ok": True, "path": self.log});
        self.outcome.append(jacsmith.BuildResult(ok=True, stage="done",
            message="fullstack app built, clicked through, and verified", files=self.log));
    }
}


"""Spawn the fullstack task-graph."""
def smith_full(task: str, work_dir: str, dry_run: bool = False) -> jacsmith.BuildResult {
    w = root spawn build_fullstack(task=task, work_dir=work_dir, dry_run=dry_run);
    jacsmith.DECL_FILE = "main.sv.jac";
    jacsmith.IMPL_FILE = "main.sv.impl.jac";
    jacsmith.ENTRY_FILE = "main.sv.jac";
    return w.outcome[0] if w.outcome else jacsmith.BuildResult(ok=False, stage="none", message="no report");
}

glob FRONT_WORDS: list[str] = ["ui", "frontend", "front-end", "web app", "webapp", "page", "website", "fullstack", "full-stack", "interface"];

def wants_frontend(task: str) -> bool {
    lowered = " " + task.lower() + " ";
    return any([(" " + w) in lowered for w in FRONT_WORDS]);
}
