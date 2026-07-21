"""gen_pairs — flywheel post-processor: trace JSONL → gate-labeled SFT records.

    jac run gen_pairs.jac -- trace1.jsonl [trace2.jsonl ...] > pairs.jsonl

Pairing rule: a slot record that carries its own `gate_ok` is self-labeled
(author_decls / repair_decls). A slot record without one (fill_impl / repair_impl)
is labeled by the NEXT gate record in the same trace file (the build/runtime gate
that judged it). Output: {"slot", "model", "input", "output", "label", "station"}.
Green teacher records are SFT gold; red/green pairs per slot feed preference tuning.
"""

import sys;
import json;

def label_stream(path: str) -> list[dict] {
    recs: list[dict] = [];
    with open(path, "r") as f {
        for line in f {
            line = line.strip();
            if line { recs.append(json.loads(line)); }
        }
    }
    pairs: list[dict] = [];
    pending: list[dict] = [];
    for r in recs {
        if r.get("kind") == "slot" {
            if "gate_ok" in r {
                pairs.append({
                    "slot": r.get("slot", ""), "station": r.get("station", ""),
                    "model": r.get("model", ""), "input": r.get("input", {}),
                    "output": r.get("output", ""), "label": bool(r["gate_ok"])
                });
            } else {
                pending.append(r);
            }
        } elif r.get("kind") == "gate" {
            for p in pending {
                pairs.append({
                    "slot": p.get("slot", ""), "station": p.get("station", ""),
                    "model": p.get("model", ""), "input": p.get("input", {}),
                    "output": p.get("output", ""), "label": bool(r.get("gate_ok", False))
                });
            }
            pending = [];
        }
    }
    return pairs;
}

with entry {
    total = 0;
    green = 0;
    for path in sys.argv[1:] {
        for p in label_stream(path) {
            print(json.dumps(p));
            total += 1;
            if p["label"] { green += 1; }
        }
    }
    print(f"# {total} pairs, {green} green", file=sys.stderr);
}
