"""jac-mini-coder mascot — the Jaseci ninja as half-block terminal pixel art.

Each grid cell is one pixel; render() folds two pixel rows into one terminal
row using ▀/▄ with truecolor fg/bg, returned as rich Text so rich can
downgrade colors on terminals without 24-bit support.

    head_lines()      20x18 banner head (9 terminal rows)
    face_lines()      12x12 avatar (6 rows)
    micro_lines()     8x6 inline face (3 rows)
    wordmark_lines()  block-letter JAC in jaseci orange
"""

import from rich.text { Text }

glob PALETTE: dict[str, str] = {
    "K": "rgb(74,74,74)",      # hood / mask — charcoal, must not vanish on dark terminals
    "O": "rgb(242,107,33)",    # jaseci orange
    "o": "rgb(249,151,30)",    # highlight orange
    "S": "rgb(246,215,176)",   # skin
    "W": "rgb(250,250,250)",   # eye white / emblem
    "B": "rgb(17,17,17)"       # pupil
};

glob HEAD: list[str] = [
    "......KKKKKKKK......",
    "....KKKKKKKKKKKK....",
    "...KKKKKKKKKKKKKK...",
    "..KKKKKKKKKKKKKKKK..",
    "..KKKKKKKKKKKKKKKK..",
    "OoooOOOOOWWOOOOOOOO.",
    "OOOOOOOOOWWOOOOOOOO.",
    ".oOOOOOOOOOOOOOOOOO.",
    ".oKSSSSSSSSSSSSSSK..",
    "..KSSKKSSSSSSKKSSK..",
    "..KSWWWKSSSSKWWWSK..",
    "..KSWBWSSSSSSWBWSK..",
    "..KSWWWSSSSSSWWWSK..",
    "..KKSSSSSSSSSSSSKK..",
    "...KKKKKKKKKKKKKK...",
    "....KKKKKKKKKKKK....",
    "...OOOOOOOOOOOOOO...",
    ".....OOOOOOOOOO....."
];

glob FACE: list[str] = [
    "...KKKKKK...",
    "..KKKKKKKK..",
    ".KKKKKKKKKK.",
    "oOOOOOOOOOOo",
    ".OOOOOOOOOO.",
    ".KSSSSSSSSK.",
    ".KSWWSSWWSK.",
    ".KSWBSSBWSK.",
    ".KKSSSSSSKK.",
    "..KKKKKKKK..",
    "...OOOOOO...",
    "....OOOO...."
];

glob MICRO: list[str] = [
    "..KKKK..",
    ".KKKKKK.",
    "OOOOOOOO",
    ".SBSSBS.",
    ".KKKKKK.",
    "..OOOO.."
];

glob JAC_WORDMARK: list[str] = [
    "     ██╗ █████╗  ██████╗",
    "     ██║██╔══██╗██╔════╝",
    "     ██║███████║██║     ",
    "██   ██║██╔══██║██║     ",
    "╚█████╔╝██║  ██║╚██████╗",
    " ╚════╝ ╚═╝  ╚═╝ ╚═════╝"
];


def _cell(top: str, bot: str) -> Text {
    t = PALETTE.get(top, "");
    b = PALETTE.get(bot, "");
    if (not t) and (not b) { return Text(" "); }
    if t and b { return Text("▀", style=t + " on " + b); }
    if t { return Text("▀", style=t); }
    return Text("▄", style=b);
}

def render(grid: list[str]) -> list[Text] {
    rows = grid if (len(grid) % 2 == 0) else (grid + ["." * len(grid[0])]);
    out: list[Text] = [];
    for y in range(0, len(rows), 2) {
        line = Text();
        for x in range(len(rows[0])) {
            line.append_text(_cell(rows[y][x], rows[y + 1][x]));
        }
        out.append(line);
    }
    return out;
}

def head_lines -> list[Text] { return render(HEAD); }
def face_lines -> list[Text] { return render(FACE); }
def micro_lines -> list[Text] { return render(MICRO); }

def wordmark_lines -> list[Text] {
    out: list[Text] = [];
    for row in JAC_WORDMARK {
        line = Text();
        for ch in row {
            if ch == "█" { line.append(ch, style="rgb(242,107,33)"); }
            elif ch != " " { line.append(ch, style="dim"); }
            else { line.append(" "); }
        }
        out.append(line);
    }
    return out;
}
