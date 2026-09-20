#!/usr/bin/env python3
"""Turn the font art and the UTF-8 string files into assembler.

    tools/mktext.py loukoumas
    tools/mktext.py mitsos

reads assets/font.txt and text/<game>.<lang>.txt and writes src/font.asm and
the game's own string table. Both outputs are committed, so building a game
needs only rasm - Python is needed when the text or the font changes.

The font is shared: it is one 8x8 set covering both scripts, drawn from
assets/font.txt and nothing else, so both games get the same src/font.asm out
of it whichever one is being built. Only the strings are per game.

Greek is folded onto the font rather than duplicated: accents are stripped
(all-caps Greek is written unaccented), lowercase is raised, and the fourteen
Greek capitals that are drawn the same as a Latin letter - Α Β Ε Ζ Η Ι Κ Μ Ν Ο
Ρ Τ Υ Χ - reuse the Latin glyph. Only ten Greek-only shapes need drawing.

Any character with no glyph is an error naming the string it came from, so a
missing letter is caught at build time rather than showing up as garbage on a
6128.
"""

import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_ART = os.path.join(ROOT, "assets", "font.txt")
GLYPH_W = 5          # mode 0 pixels drawn; the tool adds a sixth for spacing
CELL_W  = 6          # so a cell is three whole mode 0 bytes
GLYPH_H = 8

# Greek capitals whose shape is a Latin letter we already draw.
GREEK_TO_LATIN = dict(zip("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧ", "ABEZHIKMNOPTYX"))

LANGS = [("en", "ENGLISH"), ("el", "GREEK")]

#: game -> where its string table is written. The font is the same file for
#: all of them.
STRINGS = {
    "loukoumas": "src/strings.asm",
    "mitsos": "src/mitsosstr.asm",
}


def fold(ch):
    """Normalise one character onto the glyph that draws it."""
    bare = "".join(c for c in unicodedata.normalize("NFD", ch)
                   if not unicodedata.combining(c))
    bare = bare.upper()
    if not bare:
        return " "
    return GREEK_TO_LATIN.get(bare, bare)


def read_font():
    glyphs = []
    name = None
    rows = []

    def is_row(line):
        # Checked before the comment rule: a glyph row may legitimately start
        # with '#', so "looks like a row" has to win over "looks like a hash
        # comment" while a glyph is still collecting.
        return (name is not None and len(rows) < GLYPH_H and len(line) == GLYPH_W
                and not set(line) - set(".#"))

    with open(FONT_ART, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if line.startswith(":"):
                if name is not None and len(rows) != GLYPH_H:
                    sys.exit("%s:%d: glyph %s has %d rows, need %d"
                             % (FONT_ART, lineno, name, len(rows), GLYPH_H))
                if name is not None:
                    glyphs.append((name, rows))
                name = line[1:]
                rows = []
                continue
            if is_row(line):
                # Left aligned in the byte: the five drawn pixels land in bits
                # 7..3 and the spacing pixel is bit 2, so a cell is bits 7..2.
                # Small text masks off bits 7,6 three times, rotating twice
                # between, because that pair is exactly one mode 0 byte; big
                # text rotates the same six pixels out from bit 7.
                bits = int(line.replace(".", "0").replace("#", "1"), 2)
                rows.append(bits << (8 - GLYPH_W))
                continue
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            sys.exit("%s:%d: expected a glyph row of %d columns of . and #, got %r"
                     % (FONT_ART, lineno, GLYPH_W, line))
    if name is not None:
        if len(rows) != GLYPH_H:
            sys.exit("%s: glyph %s has %d rows, need %d"
                     % (FONT_ART, name, len(rows), GLYPH_H))
        glyphs.append((name, rows))
    return glyphs


def read_strings(path):
    out = {}
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                sys.exit("%s:%d: expected ID = text" % (path, lineno))
            key, val = line.split("=", 1)
            key = key.strip()
            if key in out:
                sys.exit("%s:%d: duplicate id %s" % (path, lineno, key))
            out[key] = val.strip()
    return out


#: Glyph names that are not usable as assembler labels. rasm takes ASCII
#: labels only, so the Greek-only capitals need spelling out.
ASM_NAMES = {
    " ": "SPACE", ".": "DOT", ",": "COMMA", "!": "BANG", "?": "QUERY",
    ":": "COLON", "-": "DASH", "'": "QUOTE", "/": "SLASH",
    "Γ": "GAMMA", "Δ": "DELTA", "Θ": "THETA", "Λ": "LAMBDA", "Ξ": "XI",
    "Π": "PI", "Σ": "SIGMA", "Φ": "PHI", "Ψ": "PSI", "Ω": "OMEGA",
}


def asm_label(name):
    """A label-safe spelling of a glyph name, for the GL_ constants."""
    if name == "SPACE":
        return "SPACE"
    return ASM_NAMES.get(name, name)


def main():
    game = sys.argv[1] if len(sys.argv) > 1 else "loukoumas"
    if game not in STRINGS:
        sys.exit("mktext: no such game %r - have %s"
                 % (game, ", ".join(sorted(STRINGS))))

    glyphs = read_font()
    index = {}
    for i, (name, _) in enumerate(glyphs):
        ch = " " if name == "SPACE" else name
        if ch in index:
            sys.exit("assets/font.txt: glyph %r drawn twice" % ch)
        index[ch] = i

    # Load every language and check they agree on which messages exist.
    texts = {}
    for code, _ in LANGS:
        path = os.path.join(ROOT, "text", "%s.%s.txt" % (game, code))
        texts[code] = read_strings(path)
    ids = list(texts[LANGS[0][0]])
    for code, _ in LANGS[1:]:
        missing = set(ids) - set(texts[code])
        extra = set(texts[code]) - set(ids)
        if missing or extra:
            sys.exit("text/%s.%s.txt: missing %s, unexpected %s"
                     % (game, code, sorted(missing) or "-", sorted(extra) or "-"))

    # Encode, reporting any character the font cannot draw.
    encoded = {}
    for code, _ in LANGS:
        for key in ids:
            raw = texts[code][key]
            out = []
            for ch in raw:
                g = fold(ch)
                if g not in index:
                    sys.exit("text/%s.%s.txt: %s contains %r (folds to %r), "
                             "which has no glyph in assets/font.txt"
                             % (game, code, key, ch, g))
                out.append(index[g])
            if len(out) > 255:
                sys.exit("text/%s.%s.txt: %s is longer than 255 characters"
                         % (game, code, key))
            encoded[(code, key)] = out

    write_font(glyphs)
    write_strings(game, ids, encoded)

    widest = max(len(v) for v in encoded.values())
    print("mktext: %d glyphs, %d messages x %d languages, longest %d characters"
          % (len(glyphs), len(ids), len(LANGS), widest))


def write_font(glyphs):
    path = os.path.join(ROOT, "src", "font.asm")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mktext.py from assets/font.txt - do not edit.\n")
        fh.write(";;\n;; 5x8 glyphs in a 6 pixel cell, drawn 7 tall; the sixth column and the\n")
        fh.write(";; bottom row are the spacing. Greek capitals sharing a Latin shape are not\n")
        fh.write(";; repeated; the text tool folds them onto the Latin glyph.\n\n")
        for i, (name, _) in enumerate(glyphs):
            fh.write("GL_%-6s EQU %d\n" % (asm_label(name), i))
        fh.write("\n;; Greek-only glyphs are named in full because rasm labels are ASCII:\n")
        fh.write(";; %s\n" % ", ".join(
            "%s = GL_%s" % (n, ASM_NAMES[n]) for n, _ in glyphs if n in ASM_NAMES
            and n not in " .,!?:-'/"))
        fh.write("\nGLYPH_COUNT EQU %d\n\n" % len(glyphs))
        fh.write("font\n")
        for name, rows in glyphs:
            fh.write("    ;; %s\n" % asm_label(name))
            for r in rows:
                fh.write("    defb %%%s\n" % format(r, "08b"))
        fh.write("font_end\n\n")
        fh.write("    ASSERT (font_end-font)/8 == GLYPH_COUNT\n")


def write_strings(game, ids, encoded):
    path = os.path.join(ROOT, STRINGS[game])
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(";; Generated by tools/mktext.py from text/%s.*.txt - do not edit.\n" % game)
        fh.write(";;\n;; Strings are length-prefixed runs of glyph indices, so the drawing code\n")
        fh.write(";; can centre a line without scanning it first.\n\n")
        for i, (code, name) in enumerate(LANGS):
            fh.write("LANG_%-3s EQU %d    ; %s\n" % (code.upper(), i, name))
        fh.write("LANG_COUNT EQU %d\n\n" % len(LANGS))
        for i, key in enumerate(ids):
            fh.write("MSG_%-10s EQU %d\n" % (key, i))
        fh.write("MSG_COUNT EQU %d\n\n" % len(ids))
        fh.write(";; language -> table of message pointers\nlang_tables\n")
        for code, _ in LANGS:
            fh.write("    defw msgtab_%s\n" % code)
        for code, _ in LANGS:
            fh.write("\nmsgtab_%s\n" % code)
            for key in ids:
                fh.write("    defw str_%s_%s\n" % (code, key))
        for code, _ in LANGS:
            fh.write("\n")
            for key in ids:
                data = encoded[(code, key)]
                fh.write("str_%s_%s\n" % (code, key))
                fh.write("    defb %d\n" % len(data))
                for chunk in (data[i:i + 16] for i in range(0, len(data), 16)):
                    fh.write("    defb %s\n" % ",".join(str(b) for b in chunk))


if __name__ == "__main__":
    main()
