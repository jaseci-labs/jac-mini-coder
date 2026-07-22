"""The conversational layer over the task-graphs.

Every line the user types is first understood: is it a request to BUILD/CHANGE/FIX
code, or a QUESTION to answer? Questions get a streamed, project-grounded answer;
build requests get narrated, run through the compiled task-graph, then wrapped up
in plain language (what was made, how to run it). This is what turns the tool from
a task-executor into an agent — the #1 piece of feedback.

The `llm` here is the user's chosen model (main.jac binds agent.llm alongside the
engine modules). Streaming falls back to a plain call if the transport can't stream.
"""

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
sem classify_intent = "Decide how to handle the user's message given the current project. Prefer 'chat' whenever the message is a question, a greeting, or asks how/what/why rather than requesting a change. Only choose build/add/fix when the user clearly wants code written or changed.";
sem classify_intent.message = "What the user just typed.";
sem classify_intent.project = "A summary of the current project (files, endpoints, and whether anything is built yet).";

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
