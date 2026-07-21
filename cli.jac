"""run_smith — CLI entry for the build_backend task-graph.

    jac run run_smith.jac -- "<task>" [work_dir]

Model selection (the two tiers):
    SMITH_MODEL     byllm/litellm spec (default: jacsmith's gpt-4o-mini teacher-dev default)
                    e.g. gpt-4o-mini · ollama_chat/gemma4:e4b (student on the box)
    SMITH_BASE_URL  OpenAI-compatible endpoint, e.g. http://localhost:11434 via SSH tunnel
    SMITH_DRY=1     dry run — exercise the graph + typed slots, skip disk/jac gates
"""

import os;
import sys;
import jacsmith;
import from jaclang.byllm.lib { Model }

with entry {
    args = sys.argv[1:];
    task = args[0] if len(args) > 0 else "Build a tiny notes API: create_note(title, body) and list_notes endpoints over a Note node graph.";
    work_dir = args[1] if len(args) > 1 else os.path.abspath("./out");
    dry = os.environ.get("SMITH_DRY", "") == "1";

    spec = os.environ.get("SMITH_MODEL", "");
    http_base = os.environ.get("SMITH_HTTP_BASE", "");
    if http_base {
        # http_client mode: byllm posts one JSON via httpx to the adapter
        # (byllm_adapter.py -> ollama). Used where the embedded runtime's
        # litellm transport segfaults (glibc 2.39 hosts); the adapter also
        # forces think=false and flattens parts-list content.
        jacsmith.llm = Model(
            model_name=(spec.split("/")[-1] if spec else "gemma4:e4b"),
            api_key="local",
            config={"http_client": True, "api_base": http_base, "native_tools": True}
        );
    } elif spec {
        base = os.environ.get("SMITH_BASE_URL", "");
        # native_tools=True defuses byllm's gemma name-sniff (whose tool-call
        # recovery eats any JSON output with a top-level "name" field); think=False
        # defuses gemma's thinking-channel burial. Explicit here — the toml
        # [plugins.byllm.model] section is not consulted for runtime-built Models.
        cfg: dict = {"native_tools": True};
        if base { cfg["api_base"] = base; }
        jacsmith.llm = Model(
            model_name=spec, config=cfg, call_params={"think": False}
        );
    }

    if (not dry) and (not os.path.exists(work_dir)) {
        os.makedirs(work_dir, exist_ok=True);
    }

    # route (owner=code): bare workspace → build; existing project → mutate,
    # discriminated by the task's own vocabulary (fix-words → fix_bug)
    kind = jacsmith.route(work_dir, task);
    if kind.startswith("fix_bug") {
        proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
        print("route: fix_bug @ " + proj);
        res = jacsmith.smith_fix(task, proj, dry);
    } elif kind.startswith("add_endpoint") {
        proj = kind.split(":", 1)[1] if ":" in kind else work_dir;
        print("route: add_endpoint @ " + proj);
        res = jacsmith.smith_add(task, proj, dry);
    } else {
        print("route: build_backend");
        res = jacsmith.smith(task, work_dir, dry);
    }
    print("ok=" + str(res.ok) + "  stage=" + res.stage);
    print("path: " + " -> ".join(res.files));
    if res.message {
        print(res.message[:2000]);
    }
}
