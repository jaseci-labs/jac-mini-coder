"""Reproduce gate_ui against an already-running project server (debug driver)."""
import os;
import sys;
import minicoder;
import fullstack;

with entry {
    proj = sys.argv[1] if len(sys.argv) > 1 else "";
    loaded = minicoder.load_project(proj);
    plan: minicoder.BuildPlan = loaded[0];
    print("plan.name =", plan.name);
    for e in plan.endpoints { print("  ep:", e.name, "|", e.example_json); }
    r = fullstack.gate_ui(proj, plan, os.path.join(proj, "repro_shot.png"), False, True, False);
    print("GATE_OK:", r.ok);
    print("ERRORS:", r.errors);
}
