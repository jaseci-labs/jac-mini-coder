"""temp preview: render the mascot banner exactly as main.jac composes it, to SVG."""
import mascot;
import from rich.console { Console }
import from rich.panel { Panel }
import from rich.text { Text }
import from rich { box as richbox }

with entry {
    console = Console(record=True, force_terminal=True, width=86);
    art = mascot.head_lines();
    info: list[list[str]] = [];
    info.append(["", ""]);
    info.append(["⚒ Welcome to jac-mini-coder!", "bold orange3"]);
    info.append(["write Jac with your own model — verified live", "dim"]);
    info.append(["", ""]);
    info.append(["model:     ollama_chat/gemma4:e4b", "default"]);
    info.append(["workspace: /Users/jayanaka-98/work", "default"]);
    banner = Text();
    rows = max(len(art), len(info));
    for i in range(rows) {
        if i < len(art) { banner.append_text(art[i]); }
        else { banner.append(" " * len(mascot.HEAD[0])); }
        banner.append("  ");
        if (i < len(info)) and info[i][0] {
            banner.append(info[i][0], style=info[i][1]);
        }
        if i < rows - 1 { banner.append("\n"); }
    }
    console.print("");
    console.print(Panel(banner, box=richbox.ROUNDED, border_style="orange3", expand=False, padding=(0, 1)));
    console.print("[dim]  type a task · /help for commands · /quit to exit[/dim]");
    console.print("");
    console.print("[dim]face_lines() — 6 rows:[/dim]");
    for ln in mascot.face_lines() { console.print(ln); }
    console.print("");
    console.print("[dim]micro_lines() — 3 rows:[/dim]");
    for ln in mascot.micro_lines() { console.print(ln); }
    console.print("");
    console.print("[dim]wordmark_lines():[/dim]");
    for ln in mascot.wordmark_lines() { console.print(ln); }
    svg = console.export_svg(title="jac-mini-coder");
    out = "/private/tmp/claude-501/-Users-jayanaka-98-Repos-agentic-voodoo/7abccd21-1f91-470b-a44a-325c19b1f161/scratchpad/ninja_avatar/banner_tui.svg";
    with open(out, "w") as f { f.write(svg); }
    print("wrote " + out);
}
