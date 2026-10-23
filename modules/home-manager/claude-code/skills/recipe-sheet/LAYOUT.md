# Layout

Deterministic. Follow exactly.

## Rows

Depth-first traversal, operands in graph order, emit a row at each ingredient.

This is what guarantees **contiguity**: every subtree lands on a contiguous block of rows, so a
merged cell can stand for its whole operand set. Verify contiguity anyway — a failure means the
traversal was wrong, not that the recipe was.

Order sibling branches so the one starting earliest in real time sits on top. Short garnish
branches go last.

**A leaf the traversal cannot place has no parent operation.** That is the signal that something
on the ingredient list is an accompaniment rather than an operand — rice beside a stew, bread for
sopping. It belongs in the Serve-with band. The grid finds these for you: the row comes out a
cell too wide.

## Columns

```
col(ingredient) = 0
col(operation)  = 1 + max(col(operand))
```

All offset by three, for Amount, Ingredient and Prep.

An operation at column *c* covering rows *r₁..r₂* gets `rowspan = r₂ − r₁ + 1` and
`colspan = col(parent) − c`. The root spans to the last column. An ingredient row emits
`col(parent) − 1` empty padding cells after Prep.

**Check every row:** colspans of cells starting there, plus cells spanning in from above, equal
the full width.

## Geometry

Portrait US Letter, 0.5 in margins, 10 pt body. Ingredient block 3.45 in — Amount 0.85,
Ingredient 1.60, Prep 1.00. That leaves 4.05 in for method columns, divided **evenly**.

Column count is whatever passes the **fit test**. Two conditions, both computable:

0. **Row-count precheck, before any layout work.** Every row costs at least 2 lines, so
   `rows × 2` must be under **43**. Past about **21 ingredient rows the stage cannot fit a page
   whatever you do**, and no amount of terseness or column-trimming will save it — split the stage.
   This is one count and it catches the commonest failure before the expensive arithmetic. A
   seventeen-ingredient session is already at 34 of 43 with nothing drawn.

1. **Page height.** The whole table fits the page. A cell taller than the rows it spans does not
   overflow — it **stretches those rows**, and the ingredient names beside them sit in a tall
   near-empty box. So the constraint is the sum, not the cell.

   Compute it: give every row a minimum of 2 lines — or more if its **Amount, Ingredient and Prep
   text alone** wraps past the 49-character ingredient block, measuring those three columns only
   and never the method cells, which are what the next step relaxes against. Then for each
   operation spanning rows *r₁..r₂* with *L* lines of text, raise those rows until they sum to at
   least *L*. The table's height is
   the sum of the resulting row heights, and it must fit **43 lines** — 60 on the page, less about
   17 for title, bands, target state, column heads and rules.

2. **Word floor.** Every column is at least as wide as the longest **unbreakable run** in any of
   its cells. Usually that is the longest word — *refrigerate* is twelve characters, and no amount
   of height buys that back. But a non-breaking space welds two tokens into one run: `350&nbsp;°F,`
   is twelve characters against an 11.7-character column and overflows where `350 °F,` would not.
   **Write ordinary spaces inside method cells** and keep non-breaking spaces for the bands, where
   the column is wide. When a run breaches the floor, **reword first** — *medium-high* becomes
   *medium* and the problem is gone. Drop a column only when no rewording will do it, because a
   column costs the whole sheet and a word costs one cell.

**The vertical cost of a cell is set by how few rows it spans, not by how much it says.** A long
cell on a nine-row span is free; the same text on a one-row span costs eight extra lines and
leaves one ingredient name floating in white space. A branch with a single ingredient and a fat
operation is the most expensive thing you can draw, so when the page overflows, **trim the cells
with the smallest rowspans first** — that is where the lines actually are.

| Method columns | Width | Characters | Notes |
|---|---|---|---|
| 4 | 1.01 in | 15 | comfortable |
| 5 | 0.81 in | 12 | comfortable |
| 6 | 0.67 in | 10 | ordinary cooking words start to bind |
| 7 | 0.58 in | 8 | the word floor has usually failed already |

**Seven is the ceiling**, as a backstop rather than a separate judgment. Allocate width **evenly**.
Sizing columns in proportion to their text starves the short cells, which are the ones with small
rowspans, and they overflow first.

Height is rarely the constraint: eighteen ingredient rows at two lines each, plus title, bands,
column heads and rules, come to about 49 of the 60 available lines.

Both shapes survive. Recipes come out short-and-wide — many ingredients, shallow tree, real
branching — or tall-and-thin, few ingredients and one long chain. The tall-and-thin case is the
one that tests the fit.

## Timing

1. Give every operation a `duration` range.
2. **Elapsed** = the critical path, the longest chain toward the root, low ends summed to the low
   total and high to high.
3. **Hands-on** = durations where `free` is false, plus the Prep column's work.
4. **Free** = the largest single block where `free` is true.
5. Parallel branches overlap. A branch with its own vessel starts at t=0; a branch needing the
   main vessel waits for it. A preheat fits inside any free block long enough to hold it.
6. Compare against the source's stated prep, cook and total. A gap beyond about 10% goes in the
   Timing band, stated plainly.

Print every result as a range, and say in the band when the source gave no times at all — the
sheet is then supplying a total that did not previously exist.

## HTML contract

One self-contained file. **No external dependency, and no webfont link** — a sheet whose value is
fixed geometry cannot afford to reflow because a font failed to load. Use a system stack with a
condensed face first and a normal-width fallback.

- One table. Nothing can drift out of alignment if everything shares a grid.
- Tabular numerals throughout, so quantities line up down the Amount column.
- Amount right-aligned. Ingredient and Prep left-aligned. Method cells left-aligned, because a
  fused cue reads as a sentence and centring breaks it.
- The three ingredient columns share borders and read as one block; method cells are separately
  ruled with hairlines.
- **Frame the chart on all four edges.** The ingredient columns suppress their side borders so the
  block reads as one unit, and padding cells suppress everything, which leaves the table open at
  the left and right. Give the table its own 1 pt border: under `border-collapse`,
  `border-style: none` has the lowest priority in the collapsing rules, so the frame wins over the
  cells that turn theirs off, and the ingredient block still coheres.
- **A padding cell is inside the block to its right, not outside it.** Suppress the vertical edge
  it shares with that operation, so the operation's box opens leftward across the empty space it
  governs; `border-right: hidden` does this, because `hidden` outranks everything when borders
  collapse, where `none` outranks nothing. Where that operation **ends on this row**, the padding
  cell carries the bottom border, so the block's bottom line runs left to the ingredient boundary.
  A block that reaches one row deeper than its neighbour then reads as one shape rather than as a
  box beside a hole.
- **Four rule weights, ranked.** 1.5 pt closes the header bands, 1.25 pt sits under the column
  heads, 1 pt frames the chart, hairlines divide the cells. Giving the column heads the same
  weight as the bands puts three heavy horizontals in competition and the eye loses which one is
  the boundary.
- **One rule between the bands and the target line, not two.** The bands close with their own
  heavy rule, so the target line opens straight underneath it. A second border there costs a line
  of page budget and reads as a stray divider.
- Condensed face in the body, normal width in the title.
- The **free** mark is a tint plus a heavy left edge, and always sits beside a duration, so it
  explains itself without a key.
- Print stylesheet: one page per stage, 10 pt body, page breaks only at stage boundaries.
- No `overflow` property on the page element. A sheet that can scroll is a sheet that fits by
  hiding something, and print has no scrollbar to hide it with.
- No horizontal scrolling at any width, and no font size below 10 pt. If it does not fit, the
  staging was wrong.
- The table stays a table at every width. The geometry is the content, so it never reflows into a
  stack of cards.

Markdown cannot express rowspan, so HTML is required. If plain text is demanded, render an ASCII
grid and say it is a degraded fallback.
