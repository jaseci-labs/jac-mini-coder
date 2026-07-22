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
import minicoder;
import from jaclang.byllm.lib { Model, Image }

glob JAC: str = os.path.expanduser("~/.local/bin/jac");

glob llm: Model = Model(
    model_name="ollama_chat/gemma4:e4b",
    config={"native_tools": True},
    call_params={"think": False}
);

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

obj ThemeTokens {
    has bg: str = "#f7f7f5";
    has card: str = "#ffffff";
    has ink: str = "#23262e";
    has muted: str = "#6b7078";
    has line: str = "#e4e3df";
    has accent: str = "#4f46e5";
    has accent_ink: str = "#ffffff";
    has radius: str = "10px";
}
sem ThemeTokens = "A small design-token palette for the page. Every colour is a #rrggbb hex string.";
sem ThemeTokens.bg = "Page background.";
sem ThemeTokens.card = "Card/surface background, sitting on top of bg.";
sem ThemeTokens.ink = "Primary text colour — must have strong contrast against card.";
sem ThemeTokens.muted = "Secondary text colour — readable but quieter than ink.";
sem ThemeTokens.line = "Hairline border colour, subtle against card.";
sem ThemeTokens.accent = "The single accent colour, used on the primary button.";
sem ThemeTokens.accent_ink = "Text colour ON the accent button — usually #ffffff or #000000, whichever contrasts.";
sem ThemeTokens.radius = "Corner radius with unit, e.g. '10px' or '9999px' for pill shapes.";

def pick_theme(brief: str, guide: str) -> ThemeTokens by llm(temperature=0.2);
sem pick_theme = "Choose the design tokens for this app. If the request references a well-known product or brand, match that product's actual look — its background, text and signature accent colour — so the result is visually recognisable. Otherwise choose a calm palette that suits the subject. Contrast must stay legible: ink on card, accent_ink on accent.";
sem pick_theme.brief = "What the app is, and any visual direction the user asked for.";
sem pick_theme.guide = "The design standards to respect.";

glob HEXRE: str = "^#[0-9a-fA-F]{6}$";

"""Model-picked palettes are validated mechanically: a bad hex silently breaks
the whole stylesheet, so anything malformed falls back to the default token."""
def sanitize_theme(t: ThemeTokens) -> ThemeTokens {
    d = ThemeTokens();
    if re.match(HEXRE, str(t.bg)) is None { t.bg = d.bg; }
    if re.match(HEXRE, str(t.card)) is None { t.card = d.card; }
    if re.match(HEXRE, str(t.ink)) is None { t.ink = d.ink; }
    if re.match(HEXRE, str(t.muted)) is None { t.muted = d.muted; }
    if re.match(HEXRE, str(t.line)) is None { t.line = d.line; }
    if re.match(HEXRE, str(t.accent)) is None { t.accent = d.accent; }
    if re.match(HEXRE, str(t.accent_ink)) is None { t.accent_ink = d.accent_ink; }
    if re.match(r"^[0-9]+(px|rem|em)$", str(t.radius)) is None { t.radius = d.radius; }
    return t;
}

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

def plan_fields(plan: minicoder.BuildPlan) -> list[str] {
    # the UI's form maps to the PRIMARY write endpoint only — mixing payloads
    # from several writes produced forms referencing fields the node lacks
    out: list[str] = [];
    wname = write_walker_name(plan);
    for e in plan.endpoints {
        if e.name != wname { continue; }
        try {
            pd = json.loads(e.example_json);
            for k in pd.keys() {
                if k != "reports" and str(k) not in out { out.append(str(k)); }
            }
        } except Exception {}
    }
    return out;
}

"""Fields the USER types. Under auth the identity field is filled from the
session, so it must not appear as an input the user can spoof — but it stays on
the card so you can still see who posted."""
def form_fields(plan: minicoder.BuildPlan, auth: bool) -> list[str] {
    fs = plan_fields(plan);
    if not auth { return fs; }
    kept = [f for f in fs if not minicoder.is_identity_field(f)];
    return kept if kept else fs;
}

def write_walker_name(plan: minicoder.BuildPlan) -> str {
    for e in plan.endpoints {
        if not minicoder._is_read_endpoint(e.name) { return e.name; }
    }
    return "";
}

def list_walker_name(plan: minicoder.BuildPlan) -> str {
    for e in plan.endpoints {
        if minicoder._is_read_endpoint(e.name) and (not minicoder._is_agg_endpoint(e.name)) {
            return e.name;
        }
    }
    return "";
}

glob NL: str = chr(10);
glob DQ: str = chr(34);

def render_style_css(t: ThemeTokens) -> str {
    lines = [
        ":root { --accent: " + t.accent + "; --accent-ink: " + t.accent_ink + "; --bg: " + t.bg
            + "; --card: " + t.card + "; --ink: " + t.ink + ";",
        "        --muted: " + t.muted + "; --line: " + t.line + "; --radius: " + t.radius + "; }",
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
        ".entry-form button { padding: 10px 18px; font-size: 15px; font-weight: 600; color: var(--accent-ink);",
        "  background: var(--accent); border: none; border-radius: var(--radius); cursor: pointer; }",
        ".entry-form button:hover { filter: brightness(1.08); }",
        ".card-list { display: flex; flex-direction: column; gap: 10px; }",
        ".card { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);",
        "  padding: 14px 16px; display: flex; flex-direction: column; gap: 2px; }",
        ".card strong { font-size: 15.5px; }",
        ".card span { color: var(--muted); font-size: 14px; }",
        ".empty { border: 1.5px dashed var(--line); border-radius: var(--radius); padding: 32px 16px;",
        "  text-align: center; color: var(--muted); }",
        ".auth-card { display: flex; flex-direction: column; gap: 10px; background: var(--card);",
        "  border: 1px solid var(--line); border-radius: var(--radius); padding: 24px; max-width: 360px; }",
        ".auth-card input { padding: 10px 12px; font-size: 15px; border: 1px solid var(--line);",
        "  border-radius: var(--radius); }",
        ".auth-card input:focus { outline: 2px solid var(--accent); outline-offset: 1px; }",
        ".auth-row { display: flex; gap: 8px; }",
        ".auth-row button { flex: 1; padding: 10px 14px; font-size: 15px; font-weight: 600;",
        "  border-radius: var(--radius); cursor: pointer; border: 1px solid var(--accent); }",
        ".auth-row button[type=submit] { background: var(--accent); color: var(--accent-ink); }",
        ".auth-row button[type=button] { background: var(--card); color: var(--accent); }",
        ".auth-msg { color: #b4232a; font-size: 14px; margin: 0; }",
        ".logout { float: right; margin-top: -56px; background: none; border: 1px solid var(--line);",
        "  border-radius: var(--radius); padding: 6px 12px; color: var(--muted); cursor: pointer; }",
        ".ask-card { display: flex; gap: 8px; margin-top: 28px; }",
        ".ask-card input { flex: 1; padding: 10px 12px; font-size: 15px; border: 1px solid var(--line);",
        "  border-radius: var(--radius); background: var(--card); }",
        ".ask-card input:focus { outline: 2px solid var(--accent); outline-offset: 1px; }",
        ".ask-card button { padding: 10px 18px; font-weight: 600; color: var(--accent); background: var(--card);",
        "  border: 1px solid var(--accent); border-radius: var(--radius); cursor: pointer; }",
        ".ask-card button:hover { background: var(--accent); color: var(--accent-ink); }",
        ".ai-answer { background: var(--card); border-left: 3px solid var(--accent); border-radius: var(--radius);",
        "  padding: 12px 16px; margin-top: 10px; color: var(--ink); font-size: 14.5px; white-space: pre-wrap; }"
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

def render_frontend_cl(plan: minicoder.BuildPlan, copy: UiCopy, auth: bool = False, nt: str = "", ai: bool = False, theme: ThemeTokens = ThemeTokens()) -> str {
    fields = plan_fields(plan);
    ffields = form_fields(plan, auth);
    node_t = nt if nt else minicoder._derive_node_name(plan);
    wname = write_walker_name(plan);
    lname = list_walker_name(plan);
    q = DQ;
    L: list[str] = [];
    L.append(q + q + q + copy.title + " — client UI." + q + q + q);
    L.append("");
    if auth {
        L.append("import from " + q + "@jac/runtime" + q + " { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }");
    }
    imp: list[str] = [node_t];
    if wname { imp.append(wname); }
    if lname and (lname != wname) { imp.append(lname); }
    if ai { imp.append("ask_ai"); }
    L.append("sv import from endpoints { " + ", ".join(imp) + " }");
    L.append("");
    L.append("glob PAGE_CSS: str = " + q + css_one_line(render_style_css(theme)) + q + ";");
    L.append("");
    L.append("def:pub app -> JsxElement {");
    L.append("    has items: list[" + node_t + "] = [];");
    if auth {
        L.append("    has authed: bool = False;");
        L.append("    has email: str = " + q + q + ";");
        L.append("    has password: str = " + q + q + ";");
        L.append("    has auth_msg: str = " + q + q + ";");
    }
    for f in ffields { L.append("    has " + f + ": str = " + q + q + ";"); }
    if ai {
        L.append("    has ai_q: str = " + q + q + ";");
        L.append("    has ai_a: str = " + q + q + ";");
    }
    L.append("");
    L.append("    can with entry {");
    if auth {
        L.append("        authed = jacIsLoggedIn();");
        L.append("        if authed { loadItems(); }");
    } else {
        L.append("        loadItems();");
    }
    L.append("    }");
    L.append("");
    L.append("    async def loadItems -> None;");
    if wname { L.append("    async def submitItem(e: FormEvent) -> None;"); }
    if ai {
        L.append("    async def doAsk(e: FormEvent) -> None;");
    }
    if auth {
        L.append("    async def doLogin(e: FormEvent) -> None;");
        L.append("    async def doSignup -> None;");
        L.append("    def doLogout(e: MouseEvent);");
    }
    L.append("");
    L.append("    return <div className=" + q + "shell" + q + ">");
    L.append("        <style>{PAGE_CSS}</style>");
    L.append("        <header className=" + q + "head" + q + ">");
    L.append("            <h1>" + copy.title + "</h1>");
    L.append("            <p className=" + q + "tagline" + q + ">" + copy.tagline + "</p>");
    L.append("        </header>");
    if auth {
        L.append("        {if not authed {");
        L.append("            <form className=" + q + "auth-card" + q + " onSubmit={doLogin}>");
        L.append("                <input id=" + q + "a-email" + q + " type=" + q + "text" + q + " value={email}");
        L.append("                    onChange={lambda (e: ChangeEvent) { email = e.target.value; }}");
        L.append("                    placeholder=" + q + "Email" + q + " />");
        L.append("                <input id=" + q + "a-password" + q + " type=" + q + "password" + q + " value={password}");
        L.append("                    onChange={lambda (e: ChangeEvent) { password = e.target.value; }}");
        L.append("                    placeholder=" + q + "Password" + q + " />");
        L.append("                <div className=" + q + "auth-row" + q + ">");
        L.append("                    <button id=" + q + "a-login" + q + " type=" + q + "submit" + q + ">Log in</button>");
        L.append("                    <button id=" + q + "a-signup" + q + " type=" + q + "button" + q + " onClick={doSignup}>Sign up</button>");
        L.append("                </div>");
        L.append("                {if auth_msg {");
        L.append("                    <p className=" + q + "auth-msg" + q + ">{auth_msg}</p>");
        L.append("                }}");
        L.append("            </form>");
        L.append("        }}");
        L.append("        {if authed {");
        L.append("        <button id=" + q + "logout" + q + " className=" + q + "logout" + q + " onClick={doLogout}>Log out</button>");
    }
    if wname {
    L.append("        <form className=" + q + "entry-form" + q + " onSubmit={submitItem}>");
    for f in ffields {
        ph = f[0].upper() + f[1:];
        L.append("            <input id=" + q + "f-" + f + q + " type=" + q + "text" + q + " value={" + f + "}");
        L.append("                onChange={lambda (e: ChangeEvent) { " + f + " = e.target.value; }}");
        L.append("                placeholder=" + q + ph + q + " />");
    }
    L.append("            <button id=" + q + "f-submit" + q + " type=" + q + "submit" + q + ">" + copy.submit_label + "</button>");
    L.append("        </form>");
    }
    L.append("        <section className=" + q + "card-list" + q + ">");
    # (in auth mode the entry form and list render regardless, but every handler
    #  requires a session — the auth card sits above them until login; simple
    #  and safe: hide via CSS would be nicer, kept minimal)
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
    if ai {
        L.append("        <form className=" + q + "ask-card" + q + " onSubmit={doAsk}>");
        L.append("            <input id=" + q + "ai-question" + q + " type=" + q + "text" + q + " value={ai_q}");
        L.append("                onChange={lambda (e: ChangeEvent) { ai_q = e.target.value; }}");
        L.append("                placeholder=" + q + "Ask AI about your data…" + q + " />");
        L.append("            <button id=" + q + "ai-ask" + q + " type=" + q + "submit" + q + ">Ask AI</button>");
        L.append("        </form>");
        L.append("        {if ai_a {");
        L.append("            <p id=" + q + "ai-answer" + q + " className=" + q + "ai-answer" + q + ">{ai_a}</p>");
        L.append("        }}");
    }
    if auth { L.append("        }}"); }
    L.append("    </div>;");
    L.append("}");
    return NL.join(L) + NL;
}

def render_frontend_impl(plan: minicoder.BuildPlan, auth: bool = False, nt: str = "", ai: bool = False) -> str {
    fields = form_fields(plan, auth);
    wname = write_walker_name(plan);
    lname = list_walker_name(plan);
    q = DQ;
    kwargs = ", ".join([f + "=" + f for f in fields]);
    L: list[str] = [];
    L.append(q + q + q + "Frontend handler implementations." + q + q + q);
    L.append("");
    if auth {
        L.append("impl app.doLogin(e: FormEvent) -> None {");
        L.append("    e.preventDefault();");
        L.append("    ok: bool = False;");
        L.append("    ok = await jacLogin(email, password);");
        L.append("    if ok { authed = True; auth_msg = " + q + q + "; loadItems(); }");
        L.append("    else { auth_msg = " + q + "Invalid credentials." + q + "; }");
        L.append("}");
        L.append("");
        L.append("impl app.doSignup -> None {");
        L.append("    sres: dict | None = None;");
        L.append("    ok: bool = False;");
        L.append("    sres = await jacSignup(email, password);");
        L.append("    if not sres[" + q + "success" + q + "] { auth_msg = " + q + "Signup failed — that email may be in use." + q + "; return; }");
        L.append("    ok = await jacLogin(email, password);");
        L.append("    if ok { authed = True; auth_msg = " + q + q + "; loadItems(); }");
        L.append("    else { auth_msg = " + q + "Login after signup failed." + q + "; }");
        L.append("}");
        L.append("");
        L.append("impl app.doLogout(e: MouseEvent) {");
        L.append("    jacLogout();");
        L.append("    authed = False;");
        L.append("    items = [];");
        L.append("}");
        L.append("");
    }
    if ai {
        L.append("impl app.doAsk(e: FormEvent) -> None {");
        L.append("    e.preventDefault();");
        L.append("    if not ai_q { return; }");
        L.append("    ai_a = " + q + "Thinking…" + q + ";");
        L.append("    result = root spawn ask_ai(question=ai_q);");
        L.append("    if result.reports and len(result.reports) > 0 {");
        L.append("        ai_a = " + q + "AI: " + q + " + str(result.reports[0]);");
        L.append("    } else { ai_a = " + q + "No answer came back." + q + "; }");
        L.append("}");
        L.append("");
    }
    L.append("impl app.loadItems -> None {");
    if lname {
        L.append("    result = root spawn " + lname + "();");
        L.append("    items = result.reports;");
    } else {
        L.append("    items = [];");
    }
    L.append("}");
    L.append("");
    if wname {
        L.append("impl app.submitItem(e: FormEvent) -> None {");
        L.append("    e.preventDefault();");
        L.append("    result = root spawn " + wname + "(" + kwargs + ");");
        L.append("    if result.reports and len(result.reports) > 0 {");
        L.append("        items = items + [result.reports[0]];");
        L.append("    }");
        # write-then-REFETCH (the canonical Jac mutation handler). Appending the
        # write's own report is not enough: on a shared/commons write the fresh
        # node may not come back hydrated, and other users' rows are missing
        # entirely — the row lands in the graph but the page never shows it.
        # NO post-write refetch. It was added on reasoning ("write-then-refetch
        # is canonical") and MEASURED WORSE: loadItems assigns
        # `items = result.reports`, and that read comes back from the client's
        # reader cache (the empty list from page load), wiping the optimistic
        # append — the page showed "No tweets found" right after a successful
        # post. Append-only renders correctly in manual drives. Other users'
        # rows arrive on the next mount/refresh.
        for f in fields { L.append("    " + f + " = " + q + q + ";"); }
        L.append("}");
    }
    return NL.join(L) + NL;
}

"""The generated app's AI runtime — code-owned, written at scaffold time,
NEVER part of the model's authoring/repair canvas. The app follows the user's
jac-mini-coder model choice: env first (JAC_AI_MODEL / JAC_AI_API_KEY /
JAC_AI_HTTP_BASE), then ~/.jac-mini-coder/config.json, then local ollama.
The API key is read at serve time — never baked into generated source."""
def render_ai_module -> str {
    q = DQ;
    L: list[str] = [];
    L.append("import from jaclang.byllm.lib { Model }");
    L.append("import os;");
    L.append("import json;");
    L.append("");
    L.append("def _ai_conf(field: str) -> str {");
    L.append("    try {");
    L.append("        with open(os.path.expanduser(" + q + "~/.jac-mini-coder/config.json" + q + ")) as f {");
    L.append("            return str(json.load(f).get(field, " + q + q + "));");
    L.append("        }");
    L.append("    } except Exception { return " + q + q + "; }");
    L.append("}");
    L.append("");
    L.append("glob AI_HTTP: str = os.environ.get(" + q + "JAC_AI_HTTP_BASE" + q + ", os.environ.get(" + q + "JACMINI_HTTP_BASE" + q + ", os.environ.get(" + q + "SMITH_HTTP_BASE" + q + ", _ai_conf(" + q + "http_base" + q + "))));");
    L.append("glob AI_MODEL: str = os.environ.get(" + q + "JAC_AI_MODEL" + q + ", " + q + q + ") or _ai_conf(" + q + "model" + q + ") or " + q + "ollama_chat/gemma4:e4b" + q + ";");
    L.append("glob AI_KEY: str = os.environ.get(" + q + "JAC_AI_API_KEY" + q + ", " + q + q + ") or _ai_conf(" + q + "api_key" + q + ");");
    L.append("glob AI_BASE: str = os.environ.get(" + q + "JAC_AI_API_BASE" + q + ", " + q + q + ") or _ai_conf(" + q + "api_base" + q + ");");
    L.append("");
    L.append("# byLLM drops a config-supplied api_base on its litellm branch (it pops it");
    L.append("# into self.api_base but never forwards it); re-inject on that branch so a");
    L.append("# coding-plan / gateway base URL reaches litellm. No-op without a base.");
    L.append("def _patch_byllm() {");
    L.append("    if getattr(Model, " + q + "_jmc_api_base_patched" + q + ", False) { return; }");
    L.append("    orig: any = Model.model_call_no_stream;");
    L.append("    def wrapped(slf: any, params: any) -> any {");
    L.append("        b = slf.config.get(" + q + "base_url" + q + ") or slf.config.get(" + q + "host" + q + ") or slf.config.get(" + q + "api_base" + q + ");");
    L.append("        if b and (not getattr(slf, " + q + "http_client" + q + ", False)) and (not getattr(slf, " + q + "proxy" + q + ", False)) {");
    L.append("            if isinstance(params, dict) and (not params.get(" + q + "api_base" + q + ")) { params[" + q + "api_base" + q + "] = b; }");
    L.append("        }");
    L.append("        return orig(slf, params);");
    L.append("    }");
    L.append("    setattr(Model, " + q + "model_call_no_stream" + q + ", wrapped);");
    L.append("    setattr(Model, " + q + "_jmc_api_base_patched" + q + ", True);");
    L.append("}");
    L.append("with entry { _patch_byllm(); }");
    L.append("");
    L.append("glob llm: Model = Model(");
    L.append("    model_name=(AI_MODEL.split(" + q + "/" + q + ")[-1] if AI_HTTP else AI_MODEL),");
    L.append("    api_key=(" + q + "local" + q + " if AI_HTTP else AI_KEY),");
    L.append("    config=({" + q + "http_client" + q + ": True, " + q + "api_base" + q + ": AI_HTTP, " + q + "native_tools" + q + ": True} if AI_HTTP else ({" + q + "native_tools" + q + ": True, " + q + "api_base" + q + ": AI_BASE} if AI_BASE else {" + q + "native_tools" + q + ": True})),");
    L.append("    call_params=({" + q + "think" + q + ": False} if AI_MODEL.startswith(" + q + "ollama" + q + ") else {" + q + "max_tokens" + q + ": 8000})");
    L.append(");");
    L.append("");
    L.append("def ai_answer(question: str, context: str) -> str by llm(temperature=0.3);");
    L.append("sem ai_answer = " + q + "Answer the user's question using ONLY their data given as context. Be brief and specific; if the context has no answer, say so plainly." + q + ";");
    L.append("sem ai_answer.question = " + q + "The user's question." + q + ";");
    L.append("sem ai_answer.context = " + q + "The user's stored items, serialized." + q + ";");
    return NL.join(L) + NL;
}


def render_main_entry(plan: minicoder.BuildPlan, copy: UiCopy, nt: str = "") -> str {
    node_t = nt if nt else minicoder._derive_node_name(plan);
    q = DQ;
    wnames = ", ".join([e.name for e in plan.endpoints]);
    if minicoder.ACCESS and ("admin" in [minicoder.ACCESS.get(e.name, "") for e in plan.endpoints]) {
        # code-injected walkers must be entry-imported or they never register
        wnames = wnames + ", claim_admin";
    }
    if minicoder.AI_MODE {
        wnames = wnames + ", ask_ai";
    }
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


# ---- the two-user multi-user REST gate (owner=code) ------------------------

def _mu_user(base: str, uname: str) -> str {
    minicoder._curl_json(base + "/user/register",
        '{"identities":[{"type":"username","value":"' + uname + '"}],"credential":{"type":"password","password":"mupw12345"}}');
    login = minicoder._curl_json(base + "/user/login",
        '{"identity":{"type":"username","value":"' + uname + '"},"credential":{"type":"password","password":"mupw12345"}}');
    try { return json.loads(login)["data"]["token"]; } except Exception { return ""; }
}

"""Serve the app and assert the MULTI-USER contract with two real users:
private data must NOT cross user roots; shared data MUST; admin actions gate
on the claimed role. All derived from the plan + access map — no model."""
def gate_mu(project_dir: str, plan: minicoder.BuildPlan, access: dict[str, str],
            dry: bool, wait_s: int = 240) -> minicoder.CheckResult {
    if dry { return minicoder.CheckResult(ok=True, errors=""); }
    base = "http://localhost:" + str(minicoder.SERVE_PORT);
    subprocess.run(["pkill", "-f", "jac start .* --port " + str(minicoder.SERVE_PORT)], capture_output=True);
    srv = subprocess.Popen([JAC, "start", minicoder.ENTRY_FILE, "--port", str(minicoder.SERVE_PORT)],
                           cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
    try {
        up = False;
        for _ in range(wait_s) {
            time.sleep(1);
            if minicoder._curl_json(base + "/user/register", "{}") { up = True; break; }
        }
        if not up { return minicoder.CheckResult(ok=False, errors="MU: server never came up"); }
        ta = _mu_user(base, "mua");
        tb = _mu_user(base, "mub");
        if (not ta) or (not tb) {
            return minicoder.CheckResult(ok=False, errors="MU: could not establish two user sessions");
        }
        fails: list[str] = [];
        probes: dict[str, str] = {};
        # writes as user A
        for e in plan.endpoints {
            if minicoder._is_read_endpoint(e.name) { continue; }
            acc = access.get(e.name, "priv");
            if acc == "admin" { continue; }
            resp = minicoder._curl_json(base + "/walker/" + e.name, e.example_json, ta);
            ok = False;
            try { ok = bool(json.loads(resp).get("ok", False)); }
            except Exception {}
            if not ok { fails.append("A write " + e.name + " failed -> " + resp[:200]); }
            try {
                pd = json.loads(e.example_json);
                for k in pd.keys() {
                    v = pd[k];
                    # never probe an identity field: under auth it is filled from
                    # the session, so the value we POSTed is intentionally NOT
                    # stored and asserting on it fails a correct app
                    if minicoder.is_identity_field(str(k)) { continue; }
                    if isinstance(v, str) and len(v) >= 3 { probes[e.name] = v; break; }
                }
            } except Exception {}
        }
        # reads: isolation for priv, commons for shared
        for e in plan.endpoints {
            if not minicoder._is_read_endpoint(e.name) { continue; }
            acc = access.get(e.name, "priv");
            ra = minicoder._curl_json(base + "/walker/" + e.name, "{}", ta);
            rb = minicoder._curl_json(base + "/walker/" + e.name, "{}", tb);
            probe = "";
            for w in plan.endpoints {
                if minicoder._is_read_endpoint(w.name) { continue; }
                wacc = access.get(w.name, "priv");
                if (acc == "shared") == (wacc == "shared") and w.name in probes {
                    probe = probes[w.name];
                    break;
                }
            }
            if not probe { continue; }
            if acc == "shared" {
                if probe not in rb {
                    fails.append("SHARED " + e.name + ": user B cannot see the commons data '" + probe + "'");
                }
            } else {
                if probe not in ra {
                    fails.append("PRIV " + e.name + ": owner cannot read back their own '" + probe + "'");
                }
                if probe in rb {
                    fails.append("ISOLATION BREACH " + e.name + ": user B can see user A's private '" + probe + "'");
                }
            }
        }
        # admin: A claims first, B must be refused; B's admin action forbidden
        has_admin = "admin" in [access.get(e.name, "") for e in plan.endpoints];
        if has_admin {
            ca = minicoder._curl_json(base + "/walker/claim_admin", "{}", ta);
            cb = minicoder._curl_json(base + "/walker/claim_admin", "{}", tb);
            ca_ok = False;
            try {
                ja = json.loads(ca);
                ca_ok = bool(ja.get("ok", False)) and ('"ok"' in json.dumps(ja.get("data", {})));
            } except Exception {}
            if not ca_ok { fails.append("ADMIN: first claim (A) did not succeed -> " + ca[:150]); }
            if "taken" not in cb { fails.append("ADMIN: second claim (B) was not refused -> " + cb[:150]); }
            for e in plan.endpoints {
                if access.get(e.name, "") != "admin" { continue; }
                rb2 = minicoder._curl_json(base + "/walker/" + e.name, e.example_json, tb);
                if "forbidden" not in rb2 {
                    fails.append("ADMIN " + e.name + ": non-admin B was not refused -> " + rb2[:150]);
                }
                ra2 = minicoder._curl_json(base + "/walker/" + e.name, e.example_json, ta);
                ok2 = False;
                try { ok2 = bool(json.loads(ra2).get("ok", False)); }
                except Exception {}
                if not ok2 { fails.append("ADMIN " + e.name + ": admin A call failed -> " + ra2[:150]); }
            }
        }
        if fails {
            return minicoder.CheckResult(ok=False, errors="MULTI-USER: " + "\n".join(fails));
        }
        return minicoder.CheckResult(ok=True, errors="");
    } finally {
        srv.terminate();
    }
}


# ---- the click-through browser gate (owner=code) ---------------------------

"""Wait until the served app actually answers. A fullstack `jac start` builds the
client bundle before serving — on a modest box that is ~35s, far past the fixed
sleeps this used to do. Opening the browser early meant the signup silently
no-op'd against a dead page and the later submit had no session: the gate then
blamed the app for a 'broken write/read loop' that was never broken."""
def _wait_server(port: int, timeout_s: int = 180) -> bool {
    base = "http://localhost:" + str(port) + "/";
    waited = 0;
    while waited < timeout_s {
        try {
            r = subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", base],
                               capture_output=True, text=True, timeout=10);
            if (r.stdout or "").strip().startswith("2") { time.sleep(3); return True; }
        } except Exception {}
        time.sleep(3);
        waited += 3;
    }
    return False;
}

def _browse(args: list[str], cwd: str) -> str {
    r = subprocess.run([JAC, "browse"] + args, cwd=cwd, capture_output=True, text=True, timeout=120);
    return (r.stdout or "") + (r.stderr or "");
}

"""Drive the real rendered app: open, FILL the form with the plan's example
payload via the template's stable ids, CLICK submit, assert the written value
appears in the page, then screenshot the populated page for the vision judge."""
def gate_ui(project_dir: str, plan: minicoder.BuildPlan, shot_path: str, dry: bool, auth: bool = False, ai: bool = False) -> minicoder.CheckResult {
    if dry { return minicoder.CheckResult(ok=True, errors=""); }
    base = "http://localhost:" + str(minicoder.SERVE_PORT);
    # only the inputs the user can actually type — under auth the identity field
    # is session-supplied and has no form input to fill (or to assert on)
    fields = form_fields(plan, auth);
    wname = write_walker_name(plan);
    example: dict = {};
    for e in plan.endpoints {
        if e.name == wname {
            try { example = json.loads(e.example_json); } except Exception {}
        }
    }
    try {
        _browse(["open", base], project_dir);
        if auth {
            wa = _browse(["wait", "#a-email"], project_dir);
            if ("error" in wa.lower()) and ("time" in wa.lower()) {
                _browse(["close"], project_dir);
                return minicoder.CheckResult(ok=False,
                    errors="UI: auth card never appeared: " + wa[:300]);
            }
            _browse(["fill", "#a-email", "uiuser@example.com"], project_dir);
            _browse(["fill", "#a-password", "uipw12345"], project_dir);
            _browse(["click", "#a-signup"], project_dir);
            time.sleep(2);
        }
        w = _browse(["wait", "#f-submit"], project_dir);
        if ("error" in w.lower()) and ("time" in w.lower()) {
            _browse(["close"], project_dir);
            return minicoder.CheckResult(ok=False,
                errors="UI: the form never became actionable — page blank or crashed: " + w[:300]);
        }
        for f in fields {
            val = str(example.get(f, "example"));
            _browse(["fill", "#f-" + f, val], project_dir);
        }
        _browse(["click", "#f-submit"], project_dir);
        # POLL for the written value instead of a fixed sleep: the submit does a
        # real walker spawn + re-render, which takes seconds on a modest box. A
        # 1.5s sleep raced the round-trip and failed apps that genuinely work
        # (verified by hand: the item rendered at ~8s). Fast setups still exit
        # on the first hit.
        probe0 = str(example.get(fields[0], "")) if fields else "";
        snap = "";
        tries0 = 0;
        while tries0 < 20 {
            time.sleep(2);
            snap = _browse(["snapshot"], project_dir);
            if (not probe0) or (probe0 in snap) { break; }
            tries0 += 1;
        }
        if ai {
            _browse(["fill", "#ai-question", "Summarize what I have so far."], project_dir);
            _browse(["click", "#ai-ask"], project_dir);
            # a real answer renders with the template's "AI: " prefix — poll
            # for that marker; the Thinking… placeholder and the no-reports
            # fallback both fail the gate. The window is generous: a reasoning
            # model (GLM-5, o-series) spends a hidden thinking pass before the
            # answer, so a single grounded ai_answer can take a minute-plus —
            # a fast local model still breaks early on the first hit.
            answered = False;
            tries = 0;
            while tries < 60 {
                time.sleep(4);
                s2 = _browse(["snapshot"], project_dir);
                if "AI:" in s2 { answered = True; break; }
                if "No answer came back" in s2 { break; }
                tries += 1;
            }
            if not answered {
                _browse(["close"], project_dir);
                return minicoder.CheckResult(ok=False,
                    errors="UI: asked the AI but no real answer rendered within 240s.");
            }
        }
        _browse(["screenshot", shot_path], project_dir);
        _browse(["close"], project_dir);
        probe = str(example.get(fields[0], "")) if fields else "";
        if probe and (probe not in snap) {
            return minicoder.CheckResult(ok=False,
                errors="UI: filled and clicked the form but '" + probe
                    + "' never appeared in the page — the UI write/read loop is broken.");
        }
        return minicoder.CheckResult(ok=True, errors="");
    } except Exception as ex {
        try { _browse(["close"], project_dir); } except Exception {}
        return minicoder.CheckResult(ok=False, errors="UI: browser exercise failed: " + str(ex)[:300]);
    }
}


"""Re-render the frontend trio from the CURRENT decl before every decl gate:
the project-wide `jac check` includes the frontend, and a frontend importing a
node the model didn't name that round fails the check no matter how good the
decl is (the e2b round-coupling failure)."""
def sync_frontend(project_dir: str, plan: minicoder.BuildPlan, sk: minicoder.Skeleton,
                  copy: UiCopy, auth: bool, ai: bool, dry: bool, theme: ThemeTokens = ThemeTokens()) {
    if dry { return; }
    decl_src = "";
    for d in sk.decls {
        if ".impl." not in d.path { decl_src = d.source; }
    }
    nt_real = minicoder._first_node_type(decl_src);
    if nt_real != "Root" {
        minicoder._write(project_dir, "main.jac", render_main_entry(plan, copy, nt_real));
        minicoder._write(project_dir, "frontend.cl.jac", render_frontend_cl(plan, copy, auth, nt_real, ai, theme));
        minicoder._write(project_dir, "frontend.impl.jac", render_frontend_impl(plan, auth, nt_real, ai));
    }
}


# ---- the build_fullstack task-graph ----------------------------------------

walker build_fullstack {
    has task: str = "";
    has work_dir: str = "";
    has project_dir: str = "";
    has plan: minicoder.BuildPlan = minicoder.BuildPlan();
    has skeleton: minicoder.Skeleton = minicoder.Skeleton();
    has copy: UiCopy = UiCopy();
    has auth_mode: bool = False;
    has ai_mode: bool = False;
    has theme: ThemeTokens = ThemeTokens();
    has access: dict[str, str] = {};
    has budget: int = 3;
    has dry_run: bool = False;
    has blocks: dict[str, str] = {};
    has log: list[str] = [];
    has outcome: list[minicoder.BuildResult] = [];

    can begin with Root entry {
        self.log.append("plan");
        minicoder.DECL_FILE = "endpoints.sv.jac";
        minicoder.IMPL_FILE = "endpoints.sv.impl.jac";
        minicoder.ENTRY_FILE = "main.jac";
        self.plan = minicoder.plan_build(self.task, minicoder.BACKEND_DECL_GUIDE);
        minicoder.normalize_plan(self.plan);
        drift = minicoder.plan_fidelity(self.task, self.plan);
        if drift {
            minicoder._trace({"station": "plan", "kind": "slot", "slot": "plan_drift", "output": drift});
            try {
                self.plan = minicoder.plan_build(self.task + "\n\nIMPORTANT: name the endpoints after "
                    + "THIS request's own domain (its nouns and verbs). Do NOT reuse example names "
                    + "like create_note/list_notes.", minicoder.BACKEND_DECL_GUIDE);
                minicoder.normalize_plan(self.plan);
            } except Exception {}
        }
        minicoder._trace({"station": "plan", "kind": "slot", "slot": "plan_build",
                         "input": {"task": self.task}, "output": minicoder._plan_dict(self.plan)});
        self.ai_mode = wants_ai(self.task);
        minicoder.AI_MODE = self.ai_mode;
        if self.ai_mode {
            minicoder._trace({"station": "plan", "kind": "slot", "slot": "ai_mode", "output": True});
            # the harness provides the AI endpoint (ask_ai, injected + templated);
            # a model-planned twin (ask_assistant, chat, ...) would demand a
            # hand-rolled by-llm impl the templates cannot gate — fold it out
            non_ai = [e for e in self.plan.endpoints
                      if not any([w in e.name.lower() for w in ["ask", "assistant", "chat", "answer", "query"]])];
            if non_ai and (len(non_ai) < len(self.plan.endpoints)) {
                self.plan.endpoints = non_ai;
                minicoder._trace({"station": "plan", "kind": "slot", "slot": "ai_endpoint_fold",
                                  "output": [e.name for e in self.plan.endpoints]});
            }
        }
        brief = self.plan.summary + " Endpoints: " + ", ".join([e.name for e in self.plan.endpoints]);
        try {
            self.theme = sanitize_theme(pick_theme(self.task + " | " + brief, STYLE_JUDGMENT));
            minicoder._trace({"station": "plan", "kind": "slot", "slot": "pick_theme",
                              "output": {"bg": self.theme.bg, "accent": self.theme.accent, "ink": self.theme.ink}});
        } except Exception {}
        try {
            self.copy = style_copy(brief, STYLE_JUDGMENT);
        } except Exception {
            self.copy = UiCopy(title=self.plan.name, tagline=self.plan.summary,
                               empty_state="Nothing here yet — add the first one.",
                               submit_label="Add");
        }
        if not self.copy.title { self.copy.title = self.plan.name; }
        if not self.copy.submit_label { self.copy.submit_label = "Add"; }
        self.auth_mode = wants_auth(self.task);
        if self.auth_mode {
            keep_eps = [e for e in self.plan.endpoints if not is_auth_endpoint(e.name)];
            if keep_eps and (len(keep_eps) < len(self.plan.endpoints)) {
                dropped = [e.name for e in self.plan.endpoints if is_auth_endpoint(e.name)];
                self.plan.endpoints = keep_eps;
                minicoder._trace({"station": "plan", "kind": "slot", "slot": "auth_endpoint_fold",
                                  "output": dropped});
            }
        }
        if self.auth_mode {
            self.access = derive_access(self.plan, self.task);
            minicoder.ACCESS = self.access;
            minicoder._trace({"station": "plan", "kind": "slot", "slot": "access_map",
                             "output": self.access});
        }
        minicoder._trace({"station": "plan", "kind": "slot", "slot": "style_copy",
                         "output": {"title": self.copy.title, "tagline": self.copy.tagline}});
        s1 = here ++> minicoder.ScaffoldSt();
        s2 = s1 ++> minicoder.DeclareSt();
        s3 = s2 ++> minicoder.ImplementSt();
        s4 = s3 ++> minicoder.VerifySt();
        s4 ++> minicoder.DoneSt();
        visit s1;
    }

    # scaffold web-app + write the code-derived frontend (entry, page, impl, css)
    can do_scaffold with minicoder.ScaffoldSt entry {
        self.log.append("scaffold");
        self.project_dir = os.path.join(self.work_dir, self.plan.name);
        if not self.dry_run {
            r = subprocess.run([JAC, "create", self.plan.name, "--kind", "web-app", "--force"],
                               cwd=self.work_dir, capture_output=True, text=True);
            if (r.returncode != 0) and (not os.path.isdir(self.project_dir)) {
                self.outcome.append(minicoder.BuildResult(ok=False, stage="scaffold",
                    message=(r.stdout or "") + (r.stderr or ""), files=self.log));
                disengage;
            }
            minicoder._write(self.project_dir, "plan.json",
                            json.dumps(minicoder._plan_dict(self.plan), indent=1));
            minicoder._write(self.project_dir, "main.jac", render_main_entry(self.plan, self.copy));
            minicoder._write(self.project_dir, "frontend.cl.jac", render_frontend_cl(self.plan, self.copy, self.auth_mode, "", self.ai_mode, self.theme));
            minicoder._write(self.project_dir, "frontend.impl.jac", render_frontend_impl(self.plan, self.auth_mode, "", self.ai_mode));
            minicoder._write(self.project_dir, "frontend.css",
                            render_style_css(self.theme));
            if self.ai_mode {
                minicoder._write(self.project_dir, "ai.jac", render_ai_module());
            }
            mc = os.path.join(self.project_dir, "components", "MessageCard.cl.jac");
            if os.path.exists(mc) { os.remove(mc); }
        }
        visit [-->];
    }

    can do_declare with minicoder.DeclareSt entry {
        self.log.append("declare");
        self.skeleton = minicoder.author_decls(self.plan, minicoder.BACKEND_DECL_GUIDE);
        minicoder.force_stub_file(self.skeleton, self.plan);
        minicoder.write_all(self.project_dir, self.skeleton, self.dry_run);
        sync_frontend(self.project_dir, self.plan, self.skeleton, self.copy, self.auth_mode, self.ai_mode, self.dry_run, self.theme);
        res = minicoder.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
        minicoder._trace({"station": "declare", "kind": "slot", "slot": "author_decls", "round": 0,
                         "output": minicoder.render_decls(self.skeleton),
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        mech_n = 0;
        model_failed = False;
        while (not res.ok) and (n < self.budget) {
            if mech_n < 2 and minicoder.mechanical_decl_repair(self.skeleton, self.plan, res.errors) {
                mech_n += 1;
                self.log.append("decl-mech-repair");
                minicoder.force_stub_file(self.skeleton, self.plan);
                minicoder.write_all(self.project_dir, self.skeleton, self.dry_run);
                sync_frontend(self.project_dir, self.plan, self.skeleton, self.copy, self.auth_mode, self.ai_mode, self.dry_run, self.theme);
                res = minicoder.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
                minicoder._trace({"station": "declare", "kind": "slot", "slot": "mech_repair", "round": n,
                                 "output": minicoder.render_decls(self.skeleton),
                                 "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
                continue;
            }
            self.log.append("decl-repair-" + str(n + 1));
            # a small model can fail to emit a valid Skeleton (empty / non-JSON
            # typed output) — don't let byLLM's exception crash the whole build;
            # keep the mechanically-repaired skeleton and stop repairing.
            try {
                self.skeleton = minicoder.repair_decls(minicoder.render_decls(self.skeleton), res.errors);
            } except Exception as e {
                minicoder._trace({"station": "declare", "kind": "slot", "slot": "repair_decls_error",
                                 "round": n + 1, "output": str(e)[:300]});
                model_failed = True;
                break;
            }
            minicoder.force_stub_file(self.skeleton, self.plan);
            minicoder.write_all(self.project_dir, self.skeleton, self.dry_run);
            sync_frontend(self.project_dir, self.plan, self.skeleton, self.copy, self.auth_mode, self.ai_mode, self.dry_run, self.theme);
            res = minicoder.decl_gates(self.project_dir, self.plan, self.skeleton, self.dry_run);
            minicoder._trace({"station": "declare", "kind": "slot", "slot": "repair_decls", "round": n + 1,
                             "output": minicoder.render_decls(self.skeleton),
                             "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            msg = res.errors;
            if model_failed {
                msg = "the model couldn't produce a valid declaration for this app — it's "
                    + "likely too small for a build this complex. Try a stronger model: "
                    + "gemma4:e4b (/model ollama_chat/gemma4:e4b) or a hosted model (/model). "
                    + "Last gate errors:\n" + res.errors;
            }
            self.outcome.append(minicoder.BuildResult(ok=False, stage="decl", message=msg, files=self.log));
            disengage;
        }
        visit [-->];
    }

    can do_implement with minicoder.ImplementSt entry {
        self.log.append("implement");
        for st in self.skeleton.impl_targets {
            self.blocks = minicoder.fill_impl_blocks(self.skeleton, st, "", self.blocks,
                                                    "implement", 0, self.project_dir, self.dry_run);
            body = minicoder.assemble_impl(st, self.blocks);
            minicoder.update_impl_source(self.skeleton, st.file, body);
            if not self.dry_run { minicoder._write(self.project_dir, st.file, body); }
        }
        res = minicoder.impl_gates(self.project_dir, self.skeleton, self.dry_run);
        minicoder._trace({"station": "implement", "kind": "gate", "gate": "build", "round": 0,
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        n = 0;
        while (not res.ok) and (n < self.budget) {
            self.log.append("build-repair-" + str(n + 1));
            for st in self.skeleton.impl_targets {
                self.blocks = minicoder.fill_impl_blocks(self.skeleton, st, res.errors, self.blocks,
                                                        "implement", n + 1, self.project_dir, self.dry_run);
                body = minicoder.assemble_impl(st, self.blocks);
                minicoder.update_impl_source(self.skeleton, st.file, body);
                if not self.dry_run { minicoder._write(self.project_dir, st.file, body); }
            }
            res = minicoder.impl_gates(self.project_dir, self.skeleton, self.dry_run);
            minicoder._trace({"station": "implement", "kind": "gate", "gate": "build", "round": n + 1,
                             "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
            n += 1;
        }
        if not res.ok {
            self.outcome.append(minicoder.BuildResult(ok=False, stage="build", message=res.errors, files=self.log));
            disengage;
        }
        visit [-->];
    }

    # serve (REST regression) → click-through browser gate → vision verdict →
    # bounded CSS-only refine round ("the switcharoo")
    can do_verify with minicoder.VerifySt entry {
        self.log.append("verify");
        if self.auth_mode {
            res = gate_mu(self.project_dir, self.plan, self.access, self.dry_run, 240);
        } else {
            res = minicoder.gate_serve(self.project_dir, self.plan.endpoints, self.dry_run, 240);
        }
        minicoder._trace({"station": "verify", "kind": "gate", "gate": "runtime", "round": 0,
                         "gate_ok": res.ok, "gate_errors": res.errors[:2000]});
        if not res.ok {
            self.outcome.append(minicoder.BuildResult(ok=False, stage="runtime", message=res.errors, files=self.log));
            disengage;
        }
        if not self.dry_run {
            shot = os.path.join(self.project_dir, "ui_shot.png");
            # keep the server alive for the browser: gate_serve terminated it,
            # so start it again for the UI leg
            srv = subprocess.Popen([JAC, "start", "main.jac", "--port", str(minicoder.SERVE_PORT)],
                                   cwd=self.project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
            try {
                _wait_server(minicoder.SERVE_PORT);
                ui = gate_ui(self.project_dir, self.plan, shot, self.dry_run, self.auth_mode, self.ai_mode);
                minicoder._trace({"station": "verify", "kind": "gate", "gate": "ui", "round": 0,
                                 "gate_ok": ui.ok, "gate_errors": ui.errors[:2000]});
                if not ui.ok {
                    self.outcome.append(minicoder.BuildResult(ok=False, stage="ui", message=ui.errors, files=self.log));
                    disengage;
                }
                if os.path.exists(shot) {
                    try {
                        verdict = judge_ui(Image(shot), STYLE_JUDGMENT);
                        minicoder._trace({"station": "verify", "kind": "slot", "slot": "judge_ui",
                                         "output": {"renders": verdict.renders, "quality": verdict.quality,
                                                    "issues": verdict.issues}});
                        if verdict.issues and verdict.quality < 4 {
                            self.log.append("restyle");
                            css_path = os.path.join(self.project_dir, "frontend.css");
                            cur = open(css_path).read();
                            newcss = minicoder.strip_fences(restyle_css(
                                cur, "\n".join(verdict.issues) + "\n\n" + STYLE_JUDGMENT));
                            if newcss and (":root" in newcss or "." in newcss) {
                                minicoder._write(self.project_dir, "frontend.css", newcss);
                                clp = os.path.join(self.project_dir, "frontend.cl.jac");
                                cl_src = open(clp).read();
                                cl_new = re.sub(r"glob PAGE_CSS: str = \".*\";",
                                    "glob PAGE_CSS: str = " + json.dumps(css_one_line(newcss)) + ";",
                                    cl_src, count=1);
                                minicoder._write(self.project_dir, "frontend.cl.jac", cl_new);
                                chk = minicoder.gate_check(self.project_dir, self.dry_run);
                                if not chk.ok {
                                    minicoder._write(self.project_dir, "frontend.cl.jac", cl_src);
                                    minicoder._write(self.project_dir, "frontend.css", cur);
                                } else {
                                    minicoder._trace({"station": "verify", "kind": "slot", "slot": "restyle_css",
                                                     "output": newcss[:1500]});
                                    # fresh server so the rebuilt client ships the new styles
                                    srv.terminate();
                                    time.sleep(1);
                                    srv = subprocess.Popen([JAC, "start", "main.jac", "--port", str(minicoder.SERVE_PORT)],
                                                           cwd=self.project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL);
                                    _wait_server(minicoder.SERVE_PORT);
                                    ui2 = gate_ui(self.project_dir, self.plan, shot, self.dry_run);
                                    minicoder._trace({"station": "verify", "kind": "gate", "gate": "ui", "round": 1,
                                                     "gate_ok": ui2.ok, "gate_errors": ui2.errors[:1000]});
                                    if not ui2.ok {
                                        minicoder._write(self.project_dir, "frontend.cl.jac", cl_src);
                                        minicoder._write(self.project_dir, "frontend.css", cur);
                                    }
                                }
                            }
                        }
                    } except Exception as vex {
                        minicoder._trace({"station": "verify", "kind": "slot", "slot": "judge_ui_error",
                                         "output": str(vex)[:300]});
                    }
                }
            } finally {
                srv.terminate();
            }
        }
        visit [-->];
    }

    can do_done with minicoder.DoneSt entry {
        minicoder.DECL_FILE = "main.sv.jac";
        minicoder.IMPL_FILE = "main.sv.impl.jac";
        minicoder.ENTRY_FILE = "main.sv.jac";
        minicoder.ACCESS = {};
        minicoder.AI_MODE = False;
        minicoder._trace({"station": "done", "kind": "run", "gate_ok": True, "path": self.log});
        self.outcome.append(minicoder.BuildResult(ok=True, stage="done",
            message="fullstack app built, clicked through, and verified", files=self.log));
    }
}


"""Spawn the fullstack task-graph."""
def build_full(task: str, work_dir: str, dry_run: bool = False) -> minicoder.BuildResult {
    w = root spawn build_fullstack(task=task, work_dir=work_dir, dry_run=dry_run);
    minicoder.DECL_FILE = "main.sv.jac";
    minicoder.IMPL_FILE = "main.sv.impl.jac";
    minicoder.ENTRY_FILE = "main.sv.jac";
    minicoder.ACCESS = {};
    minicoder.AI_MODE = False;
    return w.outcome[0] if w.outcome else minicoder.BuildResult(ok=False, stage="none", message="no report");
}

glob AUTH_WORDS: list[str] = ["auth", "login", "user", "users", "account", "accounts", "multi-user", "signup", "private"];
glob SHARED_NAME_WORDS: list[str] = ["shared", "team", "board", "feed", "public", "announce",
                                     "timeline", "global", "community", "wall", "everyone"];
# phrases in the REQUEST that mean "everyone sees this", even when the endpoint
# name itself is neutral (post_tweet / list_timeline name no commons)
glob PUBLIC_INTENT: list[str] = ["public", "everyone", "every user", "all users",
                                 "other users", "shared", "global", "anyone", "each other"];

"""Does the request ask for data that all users see?"""
def wants_public(task: str) -> bool {
    t = task.lower();
    return any([p in t for p in PUBLIC_INTENT]);
}
glob ADMIN_NAME_WORDS: list[str] = ["delete", "remove", "clear", "manage", "admin"];

def wants_auth(task: str) -> bool {
    lowered = " " + task.lower() + " ";
    return any([(" " + w) in lowered for w in AUTH_WORDS]);
}

"""Mechanical access classification (owner=code): shared/team vocabulary in the
endpoint name -> the commons; admin vocabulary (when the task mentions admin)
-> role-gated; everything else -> private per-user."""
def derive_access(plan: minicoder.BuildPlan, task: str) -> dict[str, str] {
    m: dict[str, str] = {};
    t = task.lower();
    for e in plan.endpoints {
        nl = e.name.lower();
        if ("admin" in t) and any([w in nl for w in ADMIN_NAME_WORDS]) {
            m[e.name] = "admin";
        } elif any([w in nl for w in SHARED_NAME_WORDS]) {
            m[e.name] = "shared";
        } elif wants_public(task) {
            # the REQUEST says everyone sees it. Endpoint names alone missed this
            # ('post_tweet'/'list_timeline' name no commons), so every non-admin
            # endpoint became per-user private: each user saw only their OWN
            # posts — a private feed wearing a timeline's name.
            m[e.name] = "shared";
        } else {
            m[e.name] = "priv";
        }
    }
    return m;
}

# the platform already provides auth (jacSignup / jacLogin + per-user roots).
# A model-planned login/register endpoint is worse than redundant: it became the
# app's "primary write", so the main form was built from {username, password},
# and the shared-write template stored those CREDENTIALS in the public commons.
glob AUTH_EP_WORDS: list[str] = ["login", "log_in", "signin", "sign_in", "signup",
                                 "sign_up", "register", "create_user", "create_account",
                                 "authenticate", "auth"];

def is_auth_endpoint(name: str) -> bool {
    nl = name.lower();
    return any([w in nl for w in AUTH_EP_WORDS]);
}

glob AI_WORDS: list[str] = ["ai", "assistant", "agentic", "ask-ai", "chatbot", "intelligent", "llm"];

"""Word-bounded on both sides — 'ai' must not fire inside 'maintain'."""
def wants_ai(task: str) -> bool {
    lowered = " " + task.lower().replace(",", " ").replace(".", " ").replace(":", " ") + " ";
    return any([(" " + w + " ") in lowered for w in AI_WORDS]);
}

glob FRONT_WORDS: list[str] = ["ui", "frontend", "front-end", "web app", "webapp", "page", "website", "fullstack", "full-stack", "interface"];

def wants_frontend(task: str) -> bool {
    lowered = " " + task.lower() + " ";
    return any([(" " + w) in lowered for w in FRONT_WORDS]);
}
