#!/bin/bash
# box_init.sh — bring up a (fresh or rebooted) GPU box for JacSmith student runs.
# Idempotent: safe to re-run. Driven from the Mac; everything happens over ssh/scp.
#
#   ./box_init.sh                      # default host ubuntu@216.81.248.77
#   ./box_init.sh ubuntu@NEW.IP        # tomorrow's instance
#
# What it does:
#   1. native jac binary (jaseci install.sh)            → ~/.local/bin/jac
#   2. ollama + systemd override (ctx 16384, keepalive) → gemma4:e4b pulled
#   3. removes the obsolete jacshim service/artifacts (pre-root-cause workaround)
#   4. ships jacsmith.jac / run_smith.jac / gen_pairs.jac / jac.toml (from box.toml)
#   5. jac install (llm capability closure into ~/jacsmith/.jac/venv)
#   6. smoke test: typed byLLM probe (FLAT/NESTED) on gemma4:e4b — must print "ok"
#
# After it passes, a student run is:
#   ssh $BOX 'cd ~/jacsmith && export PATH="$HOME/.local/bin:$PATH" \
#     SMITH_MODEL="ollama_chat/gemma4:e4b" SMITH_TRACE=$HOME/jacsmith/trace.jsonl; \
#     jac run run_smith.jac -- "<task>" $HOME/jacsmith/out'
set -euo pipefail

BOX="${1:-ubuntu@216.81.248.77}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$BOX")

step() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

step "0 · reachability"
"${SSH[@]}" 'echo "connected: $(hostname)"; nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || echo "WARN: no GPU visible"'

step "1 · native jac binary"
"${SSH[@]}" 'export PATH="$HOME/.local/bin:$PATH"
if command -v jac >/dev/null 2>&1; then jac --version | head -1
else curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash >/dev/null 2>&1
     export PATH="$HOME/.local/bin:$PATH"; jac --version | head -1; fi'

step "2 · ollama + gemma4:e4b"
"${SSH[@]}" 'command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
sudo mkdir -p /etc/systemd/system/ollama.service.d
printf "[Service]\nEnvironment=OLLAMA_CONTEXT_LENGTH=16384\nEnvironment=OLLAMA_KEEP_ALIVE=30m\n" | sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null
sudo systemctl daemon-reload && sudo systemctl enable --now ollama && sudo systemctl restart ollama && sleep 3
ollama list | grep -q gemma4:e4b || ollama pull gemma4:e4b
ollama list'

step "3 · remove obsolete shim (pre-root-cause workaround)"
"${SSH[@]}" 'sudo systemctl disable --now jacshim 2>/dev/null; sudo rm -f /etc/systemd/system/jacshim.service; sudo systemctl daemon-reload
rm -f ~/jacsmith/mitm_ollama.py ~/jacsmith/byllm_adapter.py ~/jacsmith/shim*.jsonl ~/jacsmith/shim_err.log ~/jacsmith/adapter.jsonl ~/jacsmith/litellm_config.yaml 2>/dev/null; echo "shim gone"'

step "4 · ship jacsmith"
"${SSH[@]}" 'mkdir -p ~/jacsmith'
scp -q "$HERE/jacsmith.jac" "$HERE/run_smith.jac" "$HERE/gen_pairs.jac" "$BOX:~/jacsmith/"
scp -q "$HERE/box.toml" "$BOX:~/jacsmith/jac.toml"
echo "shipped: jacsmith.jac run_smith.jac gen_pairs.jac jac.toml"

step "5 · jac install (llm closure)"
"${SSH[@]}" 'cd ~/jacsmith && export PATH="$HOME/.local/bin:$PATH" && jac install 2>&1 | tail -1'

step "5b · byllm adapter service (embedded-litellm segfault workaround)"
# On glibc 2.39 hosts (Ubuntu 24.04) the jac binary's embedded runtime
# segfaults inside litellm's live transport (venv python is fine; httpx-in-
# embedded is fine; MockLLM is fine). Workaround: byllm http_client mode ->
# this adapter (system python3) -> ollama. Harmless to install everywhere.
scp -q "$HERE/byllm_adapter.py" "$BOX:~/jacsmith/" 2>/dev/null || true
"${SSH[@]}" 'if [ -f ~/jacsmith/byllm_adapter.py ]; then
sudo tee /etc/systemd/system/jacadapter.service >/dev/null <<UNIT
[Unit]
Description=byllm http_client to ollama adapter
After=ollama.service
[Service]
ExecStart=/usr/bin/python3 /home/ubuntu/jacsmith/byllm_adapter.py
Restart=always
User=ubuntu
[Install]
WantedBy=default.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now jacadapter && systemctl is-active jacadapter
else echo "no adapter file — skipping"; fi'

step "6 · smoke test — typed byLLM probe on gemma4:e4b"
"${SSH[@]}" 'cat > ~/jacsmith/_probe.jac <<'"'"'EOF'"'"'
"""Smoke: typed slots incl. a "name" field (the gemma-sniff trap) + nesting."""
import time;

obj Flat { has name: str = ""; has count: int = 0; }
obj Inner { has path: str = ""; }
obj Nested { has name: str = ""; has items: list[Inner] = []; }

def make_flat(hint: str) -> Flat by llm(temperature=0.1);
sem make_flat = "Produce a Flat for the hint.";
def make_nested(hint: str) -> Nested by llm(temperature=0.1);
sem make_nested = "Produce a Nested with 2 items for the hint.";

with entry {
    t = time.time();
    f = make_flat("a demo called alpha with count 2");
    print(f"FLAT ok {round(time.time()-t,1)}s: {f.name} {f.count}");
    t = time.time();
    x = make_nested("beta with items x and y");
    print(f"NESTED ok {round(time.time()-t,1)}s: {x.name} items={len(x.items)}");
}
EOF
cd ~/jacsmith && export PATH="$HOME/.local/bin:$PATH"
if timeout 300 jac run _probe.jac; then echo "DIRECT MODE OK — use SMITH_MODEL=ollama_chat/gemma4:e4b"
else echo "direct mode crashed (glibc 2.39 embedded-litellm segfault) — trying http_client mode"
     printf "import from jaclang.byllm.lib { Model }\nglob llm: Model = Model(model_name=\"gemma4:e4b\", api_key=\"local\", config={\"http_client\": True, \"api_base\": \"http://127.0.0.1:11438\", \"native_tools\": True});\nobj Flat { has name: str = \"\"; has count: int = 0; }\ndef make_flat(hint: str) -> Flat by llm(temperature=0.1);\nsem make_flat = \"Produce a Flat for the hint.\";\nwith entry { f = make_flat(\"alpha count 2\"); print(\"HTTP MODE OK:\", f.name, f.count); }\n" > /tmp/_probe_http.jac
     timeout 300 jac run /tmp/_probe_http.jac && echo "USE: SMITH_MODEL=gemma4:e4b SMITH_HTTP_BASE=http://127.0.0.1:11438"
fi'

step "done"
echo "Box ready. Student run example (pick the mode the smoke test reported):"
echo "  ssh $BOX 'cd ~/jacsmith && export PATH=\"\$HOME/.local/bin:\$PATH\" SMITH_MODEL=gemma4:e4b SMITH_HTTP_BASE=http://127.0.0.1:11438; jac run run_smith.jac -- \"Build a tiny notes API...\" \$HOME/jacsmith/out'"
