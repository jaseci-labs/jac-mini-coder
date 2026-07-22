"""The conversational layer over the task-graphs.

Every line the user types is first understood: is it a request to BUILD/CHANGE/FIX
code, or a QUESTION to answer? Questions get a streamed, project-grounded answer;
build requests get narrated, run through the compiled task-graph, then wrapped up
in plain language (what was made, how to run it). This is what turns the tool from
a task-executor into an agent — the #1 piece of feedback.

The `llm` here is the user's chosen model (main.jac binds agent.llm alongside the
engine modules). Streaming falls back to a plain call if the transport can't stream.
"""

import minicoder;
import from jaclang.byllm.lib { Model }

glob llm: Model = Model(model_name="ollama_chat/gemma4:e4b", config={"native_tools": True}, call_params={"think": False});

# multi-turn memory for the conversational replies (caller-owned; byLLM appends)
glob history: list[dict] = [];

"""The router's verdict for one user message."""
obj Intent {
    has kind: str = "chat";
    has task: str = "";
    has blurb: str = "";
}
sem Intent = "How to handle the user's message.";
sem Intent.kind = "One of: 'build' (make a new app/API from scratch), 'add' (add a feature/endpoint/frontend to the EXISTING project), 'fix' (repair a bug in the existing project), 'chat' (answer a question, explain, or converse — NO code change). Questions like 'how do I run it', 'what did you build', 'what is X' are ALWAYS 'chat'.";
sem Intent.task = "For build/add/fix: a clear one-line instruction to hand to the builder, rephrased from the user's message. Empty for 'chat'.";
sem Intent.blurb = "A short, warm one-sentence acknowledgement in first person of what you're about to do (for build/add/fix), e.g. 'Sure — I'll add a like button to the timeline.' Empty for 'chat'.";

def classify_intent(message: str, project: str) -> Intent by llm(temperature=0.2);
sem classify_intent = "Decide how to handle the user's message given the current project. Classify by GRAMMAR, not politeness: an imperative or a request asking for something to be written, added, changed, built or removed is build/add/fix even when phrased casually, tersely, or as a correction of what you just did ('no, build the frontend', 'do the UI too'). Choose 'chat' only when the user asks a question, greets you, or wants an explanation and no code needs to change. jac-mini-coder builds BOTH backends and frontends — a request for a UI, a frontend, a theme or a redesign is always actionable work, never out of scope.";
sem classify_intent.message = "What the user just typed.";
sem classify_intent.project = "A summary of the current project (files, endpoints, and whether anything is built yet).";

# Verbs that mean "change my code". An imperative built on one of these is work,
# whatever the classifier decided.
glob DO_VERBS: list[str] = ["build", "make", "create", "add", "implement", "generate",
                            "scaffold", "write", "rebuild", "redo", "redesign", "restyle",
                            "change", "update", "remove", "delete", "rename", "refactor",
                            "wire", "hook up", "set up", "give me", "i want", "i need"];
# Openers that mean "explain", when no DO_VERB is present.
glob ASK_OPENERS: list[str] = ["what", "why", "how", "who", "when", "where", "did", "does",
                               "do you", "is ", "are ", "was ", "explain", "show me",
                               "tell me", "which"];
# Politeness that wraps a real instruction. "can you build X" is a request; the
# bare interrogatives above are not.
glob REQUEST_MARKERS: list[str] = ["can you", "could you", "would you", "please",
                                   "lets ", "let's ", "go ahead", "i want", "i need"];

"""Override the classifier when the grammar is unambiguous (owner=code).

The model is the only thing standing between the user and the builder, and a
chat-biased prompt made gpt-4o-mini read "no build the full frontend." as
conversation — three times running, so the user typed the same request four
different ways and got four explanations back. A classifier this load-bearing
needs a floor that does not depend on the model's mood: a message carrying an
action verb is work, and a bare question with no action verb is chat. Anything
in between is left to the model."""
def force_kind(line: str, model_kind: str, has_project: bool) -> str {
    t = " " + line.lower().strip() + " ";
    has_do = any([(" " + v) in t for v in DO_VERBS]);
    stripped = line.lower().strip();
    asks = any([stripped.startswith(o) for o in ASK_OPENERS]) or stripped.endswith("?");
    asked_politely = any([m in t for m in REQUEST_MARKERS]);
    if has_do and ((not asks) or asked_politely) {
        # a real instruction — never let it fall through to chat
        if model_kind in ["build", "add", "fix"] { return model_kind; }
        if any([w in t for w in minicoder.FIX_WORDS]) { return "fix"; }
        return "add" if has_project else "build";
    }
    # a question that happens to name an action ("what did you build") is still a
    # question — the interrogative wins unless the user asked politely for work
    if asks { return "chat"; }
    return model_kind if model_kind else "chat";
}

"""Answer a question or hold a conversation, grounded in the project. Streams."""
def chat_reply(message: str, project: str) -> str by llm(
    stream=True,
    conversation=history,
    temperature=0.4,
    system_prompt="You are jac-mini-coder, a friendly local coding agent for the Jac language. Answer the user's question directly and concisely, grounded in their project. When they ask how to run a Jac app, the answer is normally `jac start main.jac` (a served fullstack app) or `jac run main.jac` from the project directory. Never invent endpoints that aren't in the project summary. Keep it to a few sentences unless they ask for detail."
);
sem chat_reply = "Reply to the user conversationally.";
sem chat_reply.message = "What the user asked.";
sem chat_reply.project = "The current project summary (files, endpoints, how to run it).";

"""One-line plain-language wrap-up after a build/add/fix finished. Streams."""
def wrap_up(what: str, outcome: str, run_hint: str) -> str by llm(stream=True, temperature=0.3);
sem wrap_up = "In one or two friendly sentences: if the outcome SUCCEEDED, say what they now have and give the run command verbatim. If the outcome FAILED, do NOT give a run command and do NOT tell them to run or start the project — it does not work. Say plainly which stage failed, then suggest a next step: try a stronger model with /model, or restate the request more simply.";
sem wrap_up.what = "What was requested.";
sem wrap_up.outcome = "The builder's result (ok/failed + a short message).";
sem wrap_up.run_hint = "How to run the project (a shell command), or empty if not applicable.";
