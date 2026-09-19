#!/usr/bin/env python3
"""The manual, laid out as the printed booklet that came in the disc case.

    tools/mkmanual.py MANUAL.en.md docs/manual-en.pdf

The markdown file is the source - the same one anybody reads on the web - so
there is no second copy of the text to keep in step. This lays it out A5, the
size a game manual actually was, in the game's own colours, with the screen
shots keylined the way they were pasted up in 1986.

It understands the subset of markdown the manuals are written in: headings,
paragraphs, bullet and numbered lists, tables, fenced code, block quotes,
images with the alt text as the caption, rules, and **bold** / *italic* /
`code` inline. Anything else comes through as plain text rather than as
markup, which is the right way round for a document that has to be readable
either way.
"""

import os
import re
import sys

from fpdf import FPDF
from fpdf.fonts import FontFace

#: pal_play, for the parts of the page that are not the text.
NAVY = (0, 0, 128)
CORAL = (255, 128, 128)
YELLOW = (255, 255, 0)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
GREY = (110, 110, 110)
PAPER = (250, 250, 245)
RULE = (200, 200, 200)

NOTO = "/usr/share/fonts/truetype/noto/"
DEJA = "/usr/share/fonts/truetype/dejavu/"

MARGIN = 14
IMG_W = 96                              # mm: two screen shots fit a page


def inline(text):
    """Markdown the way fpdf2 spells it: it knows **bold** and __italic__."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)        # links
    text = re.sub(r"`([^`]+)`", r"**\1**", text)                # code -> bold
    text = re.sub(r"(?<![\*\w])\*([^\*]+)\*(?!\*)", r"__\1__", text)
    return text.replace("\\", "")


def plain(text):
    return re.sub(r"[*_`]", "", inline(text))


class Manual(FPDF):
    def __init__(self, title):
        super().__init__(format=(148, 210))      # A5, the size a manual was
        self.title_text = title
        self.set_margins(MARGIN, MARGIN, MARGIN)
        self.set_auto_page_break(True, MARGIN + 6)
        for style, name in (("", "NotoSans-Condensed"),
                            ("B", "NotoSans-CondensedBold"),
                            ("I", "NotoSans-CondensedItalic"),
                            ("BI", "NotoSans-CondensedBoldItalic")):
            self.add_font("body", style, NOTO + name + ".ttf")
        self.add_font("head", "", NOTO + "NotoSans-CondensedBlack.ttf")
        self.add_font("head", "I", NOTO + "NotoSans-CondensedBlackItalic.ttf")
        self.add_font("mono", "", DEJA + "DejaVuSansMono.ttf")
        self.add_font("mono", "B", DEJA + "DejaVuSansMono-Bold.ttf")
        # The arrows in the controls table, the dots in the enemy table and
        # the stars round a heading are not in Noto Sans Condensed. DejaVu has
        # all of them, so it stands behind it for the handful of characters
        # that would otherwise come out as a missing-glyph box.
        self.add_font("fallback", "", DEJA + "DejaVuSans.ttf")
        self.add_font("fallback", "B", DEJA + "DejaVuSans-Bold.ttf")
        self.set_fallback_fonts(["fallback"])

    def footer(self):
        if self.page_no() == 1:
            return
        self.set_y(-MARGIN - 2)
        self.set_font("body", "", 7)
        self.set_text_color(*GREY)
        self.cell(0, 4, self.title_text, align="L")
        self.set_x(MARGIN)
        self.cell(0, 4, str(self.page_no()), align="R")

    # -- blocks -------------------------------------------------------------
    def heading(self, level, text):
        text = plain(text)
        if level == 1:
            self.set_font("head", "I", 26)
            self.set_fill_color(*NAVY)
            self.set_text_color(*YELLOW)
            self.multi_cell(0, 13, text, fill=True, align="C", new_x="LMARGIN",
                            new_y="NEXT")
            self.ln(3)
        elif level == 2:
            if self.will_page_break(22):
                self.add_page()
            self.ln(3)
            self.set_font("head", "", 13)
            self.set_fill_color(*NAVY)
            self.set_text_color(*WHITE)
            self.multi_cell(0, 8, "  " + text, fill=True, new_x="LMARGIN",
                            new_y="NEXT")
            self.ln(2.5)
        else:
            self.ln(2)
            self.set_font("head", "", 11)
            self.set_text_color(*NAVY)
            self.multi_cell(0, 6, text, new_x="LMARGIN", new_y="NEXT")
            x = self.get_x()
            self.set_draw_color(*CORAL)
            self.set_line_width(0.6)
            self.line(x, self.get_y(), x + 40, self.get_y())
            self.ln(2.5)
        self.set_text_color(*BLACK)

    def para(self, text, style=""):
        self.set_font("body", style, 9.5)
        self.set_text_color(*BLACK)
        self.multi_cell(0, 5, inline(text), markdown=True, new_x="LMARGIN",
                        new_y="NEXT")
        self.ln(1.6)

    def quote(self, lines):
        text = inline(" ".join(lines))
        self.set_x(MARGIN + 4)
        self.set_font("body", "I", 9)
        # Ask how tall it will be before drawing it, so the bar and its text
        # stay together on one page rather than the bar being left behind.
        tall = 4.6 * len(self.multi_cell(0, 4.6, text, markdown=True,
                                         dry_run=True, output="LINES"))
        if self.will_page_break(tall):
            self.add_page()
        y0, page = self.get_y(), self.page_no()
        self.set_x(MARGIN + 4)
        self.set_text_color(*GREY)
        self.multi_cell(0, 4.6, text, markdown=True,
                        new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(*CORAL)
        self.set_line_width(1.2)
        if self.page_no() != page:      # it broke across a page: bar the rest
            y0 = MARGIN
        self.line(MARGIN + 1, y0 + 0.5, MARGIN + 1, self.get_y() - 1)
        self.ln(2)
        self.set_text_color(*BLACK)

    def bullets(self, items, numbered=False):
        """The marker sits in the margin and the text is a column of its own:
        moving the left margin rather than the cursor is what keeps the second
        line of an item under the first instead of back at the page edge."""
        indent = 7
        for mark, item in items:
            mark = mark if numbered else "•"
            y = self.get_y()
            if self.will_page_break(10):
                self.add_page()
                y = self.get_y()
            self.set_font("body", "B", 9.5)
            self.set_text_color(*(NAVY if numbered else CORAL))
            self.text(MARGIN + 1, y + 3.7, mark)
            self.set_text_color(*BLACK)
            self.set_font("body", "", 9.5)
            self.set_left_margin(MARGIN + indent)
            self.set_xy(MARGIN + indent, y)
            self.multi_cell(0, 5, inline(item), markdown=True,
                            new_x="LMARGIN", new_y="NEXT")
            self.set_left_margin(MARGIN)
            self.set_x(MARGIN)
            self.ln(0.8)
        self.ln(1.4)

    def code(self, lines):
        self.ln(1)
        self.set_font("mono", "", 9)
        self.set_fill_color(240, 240, 235)
        self.set_text_color(*NAVY)
        for line in lines:
            self.cell(0, 5, "  " + line, fill=True, new_x="LMARGIN",
                      new_y="NEXT")
        self.set_text_color(*BLACK)
        self.ln(2.5)

    def table(self, rows):
        head, body = rows[0], rows[1:]
        self.set_font("body", "", 8.2)
        self.set_text_color(*BLACK)
        # The table takes the document's colours as its starting style, and
        # the last heading left that navy on navy. Both ends have to be said:
        # white for the rows that are not striped, grey for the ones that are.
        self.set_fill_color(*WHITE)
        style = FontFace(emphasis="BOLD", color=WHITE, fill_color=NAVY)
        with super().table(first_row_as_headings=any(c.strip() for c in head),
                           headings_style=style, markdown=True,
                           line_height=5, padding=1.4,
                           cell_fill_color=(242, 242, 238),
                           cell_fill_mode="ROWS",
                           borders_layout="SINGLE_TOP_LINE") as t:
            for r in [head] + body:
                row = t.row()
                for cell in r:
                    row.cell(inline(cell.strip()))
        self.ln(3)

    def picture(self, path, caption):
        if not os.path.exists(path):
            sys.exit("mkmanual: no such image: %s" % path)
        from PIL import Image
        w, h = Image.open(path).size
        ih = IMG_W * h / w
        if self.will_page_break(ih + 10):
            self.add_page()
        x = (self.w - IMG_W) / 2
        y = self.get_y()
        self.set_draw_color(*NAVY)
        self.set_line_width(0.5)
        self.rect(x - 0.7, y - 0.7, IMG_W + 1.4, ih + 1.4)
        self.image(path, x=x, y=y, w=IMG_W)
        self.set_y(y + ih + 1.6)
        if caption:
            self.set_font("body", "I", 8)
            self.set_text_color(*GREY)
            self.multi_cell(0, 4, plain(caption), align="C",
                            new_x="LMARGIN", new_y="NEXT")
            self.set_text_color(*BLACK)
        self.ln(3)

    def rule(self):
        self.ln(1)
        self.set_draw_color(*RULE)
        self.set_line_width(0.3)
        self.line(MARGIN, self.get_y(), self.w - MARGIN, self.get_y())
        self.ln(3)


def render(md_path, pdf_path):
    lines = open(md_path, encoding="utf-8").read().splitlines()
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), "Manual")

    pdf = Manual(title)
    pdf.set_title(title)
    pdf.add_page()

    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        m = re.match(r"^(#{1,4})\s+(.*)", stripped)
        if m:
            pdf.heading(len(m.group(1)), m.group(2))
            i += 1
            continue

        m = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$", stripped)
        if m:
            pdf.picture(m.group(2), m.group(1))
            i += 1
            continue

        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            pdf.rule()
            i += 1
            continue

        if stripped.startswith("```"):
            block, i = [], i + 1
            while i < n and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            pdf.code(block)
            i += 1
            continue

        if stripped.startswith("|"):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                cells = [c for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r"\s*:?-{2,}:?\s*", c) for c in cells):
                    rows.append(cells)
                i += 1
            if rows:
                pdf.table(rows)
            continue

        if stripped.startswith(">"):
            block = []
            while i < n and lines[i].strip().startswith(">"):
                block.append(lines[i].strip().lstrip(">").strip())
                i += 1
            pdf.quote([b for b in block if b])
            continue

        m = re.match(r"^\s*([*-]|\d+\.)\s+(.*)", line)
        if m:
            numbered = not m.group(1) in "*-"
            items = []
            while i < n:
                m = re.match(r"^\s*([*-]|\d+\.)\s+(.*)", lines[i])
                if m:
                    items.append((m.group(1), m.group(2)))
                    i += 1
                elif (re.match(r"^(\s{2,}|\t)\S", lines[i])
                        and not lines[i].strip().startswith("```")):
                    items[-1] = (items[-1][0],
                                 items[-1][1] + " " + lines[i].strip())
                    i += 1
                elif (lines[i].strip() == "" and i + 1 < n
                        and re.match(r"^\s*([*-]|\d+\.)\s+", lines[i + 1])):
                    i += 1
                else:
                    break
            pdf.bullets(items, numbered)
            continue

        block = []
        while i < n and lines[i].strip() and not re.match(
                r"^\s*(#{1,4}\s|[*-]\s|\d+\.\s|\||>|```|!\[|---)", lines[i]):
            block.append(lines[i].strip())
            i += 1
        pdf.para(" ".join(block))

    pdf.output(pdf_path)
    print("mkmanual: %s (%d pages from %s)" % (pdf_path, pdf.page_no(),
                                               os.path.basename(md_path)))


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: mkmanual.py <MANUAL.xx.md> <out.pdf>")
    render(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
