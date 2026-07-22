"""jac-mini-coder mascot — the Jaseci ninja as half-block terminal pixel art.

Each grid cell is one pixel; render() folds two pixel rows into one terminal
row using ▀/▄ with truecolor fg/bg, returned as rich Text so rich can
downgrade colors on terminals without 24-bit support.

    head_lines()      28x18 masked ninja, katana on the back (9 rows)
    face_lines()      12x12 avatar (6 rows)
    micro_lines()     8x6 inline face (3 rows)
    wordmark_lines()  block-letter JAC in jaseci orange
"""

import os;
import from rich.text { Text }

glob PALETTE: dict[str, str] = {
    "K": "rgb(74,74,74)",      # hood / mask — charcoal, must not vanish on dark terminals
    "O": "rgb(242,107,33)",    # jaseci orange
    "o": "rgb(249,151,30)",    # highlight orange
    "S": "rgb(246,215,176)",   # skin
    "W": "rgb(250,250,250)",   # eye white / emblem
    "B": "rgb(17,17,17)"       # pupil
};

# The ninja mid-throw: hood, headband, eye slit, shuriken in flight along the
# arm's line. A head alone read as a hooded face; the full figure plus the
# stars is what makes it unmistakably a ninja. Each grid is 24x18 pixels =
# 24 terminal columns by 9 rows once the half-block fold halves the height.

# a — the mascot: hood, tied headband with the jaseci emblem, swoosh eyes,
# katana strapped across the back (default)
glob NINJA_A: list[str] = [
    "..........KKKKKKKK.......oo.",
    "........KKKKKKKKKKKK....KK..",
    ".......KKKKKKKKKKKKKK..oo...",
    "......KKKKKKKKKKKKKKKKKK....",
    "......KKKKKKKKKKKKKKKK......",
    "..OO.OOOOOOOOWWOOOOOOOK.....",
    ".OOOOOOOOOOOOWWOOOOOOO......",
    "..oo..OOOOOOOOOOOOOOOO......",
    ".OO...KSSSSSSSSSSSSSSK......",
    "OO....KSBBSSSSSSSSBBSK......",
    "......KSBBBBSSSSBBBBSK......",
    "......KSSBBBBSSBBBBSSK......",
    "......KSSSSSSSSSSSSSSK......",
    ".....KKKKKKKKKKKKKKKKK......",
    "....KK.KKKKKKKKKKKKKK.......",
    "...KK...KKKKKKKKKKKK........",
    ".oKK...OOOOOOOOOOOOOO.......",
    "oKK......OOOOOOOOOO........."
];

# b — level throw, stars receding
glob NINJA_B: list[str] = [
    "........................",
    "..KKKKKK................",
    "..KKKKKK................",
    "..OOOOOO................",
    "..KSSSSK................",
    "..KBSSBK.............O..",
    "..KKKKKK.........O..OOO.",
    "...KKKK.....KKK.OOO..O..",
    "..KKKKKKKKKKK....O......",
    "..KKKKKKKK..............",
    ".OOOOOOOOO..............",
    ".KKKKKKKKK..............",
    ".KKKKKKKKK..............",
    "..KKK..KKK..............",
    "..KKK..KKK..............",
    ".KKKK..KKKK.............",
    "........................",
    "........................"
];

# c — overhead throw, stars arcing away
glob NINJA_C: list[str] = [
    "...................O....",
    "..KKKKKK..........OOO...",
    "..KKKKKK.......O...O....",
    "..OOOOOO......OOO.......",
    "..KSSSSK....K..O........",
    "..KBSSBK...KK...........",
    "..KKKKKK..KK............",
    "...KKKK...K.............",
    "..KKKKKKKK..............",
    "..KKKKKKKK..............",
    ".OOOOOOOOO..............",
    ".KKKKKKKKK..............",
    ".KKKKKKKKK..............",
    "..KKK..KKK..............",
    "..KKK..KKK..............",
    ".KKKK..KKKK.............",
    "........................",
    "........................"
];

# d — the original hand-drawn head (yours), kept as-is
glob NINJA_D: list[str] = [
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

glob HEAD_VARIANTS: dict[str, list[str]] = {
    "a": NINJA_A, "b": NINJA_B, "c": NINJA_C, "d": NINJA_D
};

# JACMINI_MASCOT=a|b|c|d picks the figure; preview with `jac run mascot.jac`
glob HEAD: list[str] = HEAD_VARIANTS.get(
    os.environ.get("JACMINI_MASCOT", "a").strip().lower(), NINJA_A);

glob FACE: list[str] = [
    "...KKKKKK...",
    "..KKKKKKKK..",
    ".KKKKKKKKKK.",
    "OOOOOOOOOOO.",
    "oKKKKKKKKKK.",
    ".KSSSSSSSSK.",
    ".KSBBSSBBSK.",
    ".KSSBSSBSSK.",
    ".KKKKKKKKKK.",
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
    # drop fully blank trailing rows, else the art contributes an empty line and
    # the banner grows a stray gap above its bottom border
    trimmed = list(grid);
    while trimmed and (set(trimmed[-1]) == {"."}) { trimmed.pop(); }
    rows = trimmed if (len(trimmed) % 2 == 0) else (trimmed + ["." * len(trimmed[0])]);
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


"""`jac run mascot.jac` — compare the heads side by side and pick one.

Colour art cannot be judged from source, so this renders every variant in the
terminal it will actually live in. Choose with JACMINI_MASCOT=a|b|c|d.
"""
with entry:__main__ {
    import from rich.console { Console }
    con = Console();
    keys = ["a", "b", "c", "d"];
    labels = ["a  ninja + katana (default)", "b  level throw", "c  overhead throw",
              "d  original head"];
    cols: list[list[Text]] = [];
    for k in keys { cols.append(render(HEAD_VARIANTS[k])); }
    con.print("");
    # variants differ in width AND height (the original head is 20 wide, the
    # throwing figures 24), so pad every column to the tallest and widest
    tall = max([len(c) for c in cols]);
    con.print("");
    for r in range(tall) {
        line = Text("  ");
        for (ci, c) in enumerate(cols) {
            w = len(HEAD_VARIANTS[keys[ci]][0]);
            if r < len(c) { line.append_text(c[r]); } else { line.append(" " * w); }
            line.append("  ");
        }
        con.print(line);
    }
    hdr = Text("  ");
    for lb in labels { hdr.append(lb.ljust(25), style="dim"); }
    con.print(hdr);
    con.print("");
    con.print("  [dim]pick one:[/dim] JACMINI_MASCOT=b jac run main.jac", highlight=False);
    con.print("");
}
