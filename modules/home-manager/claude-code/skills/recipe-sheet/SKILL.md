---
name: recipe-sheet
description: Turn a recipe into a recipe sheet — one printable page holding everything needed to cook the dish, from provisioning through storage. Use when the user supplies a recipe as a URL, prose, a photo, or their own shorthand notes and wants it rebuilt as a sheet, a chart, or a cooking reference.
---

# Recipe sheet

A recipe sheet **replaces** its source. The cook holds the sheet and nothing else. Any question
that sends them back to the original is a missing field on the sheet.

The sheet is **static**: read on a screen or on paper, never touched while cooking. Everything is
visible at once, at arm's length, in monochrome.

You are delivering a complete recipe that happens to have a source. You are not transcribing.

## What a recipe is

A recipe is a **graph**. Ingredients are the leaves. Each **operation** consumes one or more
**operands** and produces one thing. The dish is the root.

Prose splits that graph into two artifacts that never reference each other, and the cook rebuilds
it in working memory. The sheet draws it directly, using one fact:

> Order the leaves by depth-first traversal and every subtree occupies a **contiguous** block of
> rows.

So a merged cell's vertical extent **is** its operand set. Quantity sits at first use. What goes
in one bowl is answered by looking. Branches that run in parallel are vertically separate; the
column where they merge is where they must meet.

Preserve **contiguity**. It is the reason the grid carries information that would otherwise
cost words, and every other rule here defers to it.

## Run these steps in order

### 1. Read the whole source first

Fetch a URL and extract everything, including the notes or "playing around" section most scrapers
drop — Swaps and Make ahead live there. Work from prose, a photo, or shorthand notes as given.

**Done when:** you can state the finished dish's target state in one line — what it looks like,
how thick, what colour — from the source alone or from knowing the dish.

### 2. Build the graph

Model the real dependencies as a **DAG**, in the shape at `IR.md`. An intermediate may feed two
operations; one operation may yield two products. Record what is true, then let the rendering lose
what a grid cannot draw, per §Degrading a DAG below.

**Done when:** exactly one root, everything reachable, no cycles, and every ingredient in the
source appears in the graph.

### 3. Apply the arity gate to every ingredient

**Arity** decides where an ingredient's own preparation lives. Check arity before anything else.

| Operands | Can it wait? | Where it goes |
|---|---|---|
| Two or more | irrelevant | **operation cell** |
| One | needs a moment, vessel, time or temperature | **operation cell** |
| One | any time, any vessel, any order | **Prep** column |
| None | goes in as it comes | Prep column, written `—` |

Sifting flour, cocoa and soda together is any-time work and still an operation cell: those three
become one object, and the geometry exists to show exactly that. **Arity outranks convenience.**

Write `—` rather than leaving a Prep cell empty. A dash reads as a decision; a blank reads as an
oversight.

Recipes name ingredients in two places and the lists disagree. Take every ingredient the
**method** uses, not only the ones the list declares — a set of notes may call for oil, broth and
salt in its steps and name none of them. Say on the row where it came from.

**Done when:** every ingredient row has a Prep value, no cell in the Prep column combines two
ingredients, and every ingredient named in either the list or the method is on the sheet.

### 4. Schedule and time

Compute; do not copy. Full method at `LAYOUT.md` §Timing.

Give every operation a duration **range**. Take it from the source where the source gives one,
work it out where the source does not. Carry ranges through the arithmetic — low ends sum to the
low total, high ends to the high. A cook can plan around "45 to 70 minutes"; a cook cannot plan
around one number that is quietly a guess.

Assume **one cook with one pair of hands and one attention**. A branch with its own vessel starts
at t=0; a branch needing the main vessel waits. A preheat fits inside any unattended block long
enough to hold it. Order sibling branches so the one starting earliest in real time sits on top:
the first row is the first thing you do.

**Done when:** hands-on, free, and elapsed are all ranges, and any disagreement with the source's
stated times of more than ~10% is stated in the Timing band.

### 5. Stage the sheet

Column count grows with tree depth. How many fit is decided by the **fit test** at
`LAYOUT.md` §Geometry — the whole table fits 43 lines once rows stretch to hold their tallest
cell, and every column is at least as wide as its longest word — with seven columns as a backstop
ceiling.

When the fit test fails, first look for operations that merge. A **transition that needs
no decision and has no separate stop** is a parameter of the next operation, not an operation:
*bring to a boil, then simmer until thickened* is one cell, and so is *slice once cool enough to
handle*. One vessel, one continuous act, one stop condition — that is one operation.

If the fit test still fails, split into **stages**. A stage break is legal where all three hold:

1. **Hands** — nothing is mid-flight. The cook can stop, wipe down, and turn the page. Thirty
   seconds is long enough; duration does not matter.
2. **Everything forward** — everything needed from here on lives on this page and the ones after:
   quantities, prep, equipment, target state.
3. **Closure** — everything carried across the break is named, and enters the next stage as a
   leaf with its own row.

**A break lands after a free block, and this outranks everything else here.** The cook physically
leaves during the chill, the rise, the simmer — so the page they are holding when they walk away
should be finished. Put the free block at the foot of the page and the turn happens when they
come back, hands clean. Put it at the head of the next page and they turn to a sheet they cannot
use for two hours.

Otherwise pack **late**: fill the page, and when the next operation fails the fit test, back up to
the latest legal pause that still passes. A page turn costs a handwash, so buy as few as possible.
Let a short final stage stand: an early break costs a handwash on every cook forever, and a
half-empty page costs paper once.

Where a stretch offers no legal pause and still overflows, break anyway, and say on the page that
the break is forced and why.

**Compute the fit; estimating it by eye fails.** Two tiers:

- **Row-count precheck.** `rows × 2` under 43, before anything else. Past about **21 ingredient
  rows the stage cannot fit a page whatever you do** — split it. Column depth is not the only
  reason to stage, and this is one count that catches the commonest failure early.
- **Fast check.** If every cell's text is under `rowspan × 2 × chars_per_column` characters, no row
  stretches, the table is exactly `2 × rows` lines, and you are done. This is sufficient, not
  necessary — failing it does not mean the sheet overflows.
- **Full check.** If any cell fails the fast check, run the relaxation at `LAYOUT.md` §Geometry.
  It is a loop over row heights and takes a dozen lines of code. Run it rather than guessing.

**Done when:** every stage passes the fit test, every break satisfies all three conditions or is
marked as forced, and every free block long enough to leave the kitchen sits at the foot of a
page.

### 6. Render

Full geometry, spans, and the HTML contract at `LAYOUT.md`.

**Title line**, above the bands, carrying: dish name, yield, source with its locator, and the
**version date**. On a multi-stage sheet each page also carries *page n of m*, a one-line stage
label, the equipment first needed on that page, and the wall clock remaining from the top of that
page. The version date goes here on every page — a stale printout is otherwise indistinguishable
from a current one at arm's length.

**Bands.** Labelled categories holding everything true *before you pick up a knife*:
Equipment, Timing, the appliance and its settings, Make ahead, Swaps, Serve with, and one line of
**target state**. Include a category when it has something real in it. Food that gets sliced,
drained or brought to temperature belongs in the body, not the bands.

On a multi-stage sheet, page one also carries a **Shopping** band naming any ingredient whose
quantity is split across stages. A cook holding page three cannot see a total that sits on page
one, and provisioning is asked cold, before anything starts, which is where that band is.

Derive Equipment by walking the operations rather than copying the source: the second pan a
parallel branch implies, the colander a *drained and rinsed* implies, the freezer space two dough
logs imply.

**Verbs.** Terse imperative, articles dropped, and the operand left unnamed — the cell's vertical
extent already says what goes in. Repeating a verb is correct; column position separates two
`add`s, so keep the plain word.

**Cues govern clocks.** The stop condition is the instruction and the clock is a hint. Write the
clock as a range beside it. Where a clock genuinely governs — a timed brine, minutes under
pressure — say so in the cell.

Most operations have a cue. **Combining steps are the exception**: an operation with no heat and
no chemistry, where the act itself is the completion, has no signal to watch for. *Stir in* is
finished when everything is in. Leave its cue blank rather than inventing *evenly combined*,
which teaches the cook that cues are decoration. The test is narrow on purpose — heat or chemistry
present means a cue exists and you find it.

**Fuse what changes what the cook does.** A reason that changes what they watch for, and a failure
that is irreversible or invisible at the time, both belong **in the operation cell**, in the
fewest words that work: **20 words per note, and 2 notes per page.** A mark sits beside a note, not inside it, and does not count toward its 20. Past that you are writing
prose in a cell and the rows stretch to hold it, which is what pushes a sheet over the page.
*Add garlic, 1 min exactly — it burns and turns bitter past that.* If a third note seems
necessary, one of the three is describing something the cue should already say. **Add no footer and no numbered notes.** Another guardrail. Every one of them belongs somewhere
better: a reason or a failure goes in its cell, a swap or a timing conflict goes in its band, and
provenance goes in the response rather than on the page. A note eleven inches from the pan is a
note the cook reads afterwards.

**Name an intermediate** when two exist at once, and always when one crosses a stage break.

### 7. Mark, in three channels

| Channel | Means | Rendered as |
|---|---|---|
| **Free** | your attention is free here | tint and a heavy left edge, always beside a duration |
| **Precision** | this number is not negotiable | the word `exactly`, or `keep to` |
| **Inferred** | this is a judgment call; make a different one if you like | the words `(not stated)` or `(inferred)` |

One visual mark and two verbal ones, so the sheet explains itself and a first-time reader decodes
it on sight. Every mark is carried by tint, edge or wording, so all of them survive greyscale and
colour-blind reading.

**Add no key and no legend.** This is a guardrail, not a preference: a key is only needed by a
notation that fails to explain itself, and adding one repeats the same three lines on every sheet
you ever print. If a mark seems to need explaining, reword the mark.

Free and Precision are independent of Inferred: a source-stated ¼ tsp of baking soda is precise
and stated; a cut of garlic the source omits is negotiable and inferred; a pot's minimum liquid is
non-negotiable and inferred. All four combinations occur.

**Mark an inference only where the other reading materially changes the dish.** Triggers:

- a quantity that could swing by more than about half again
- a technique whose alternatives give different texture or different results
- a duration or temperature the source defers to something the sheet cannot see
- an ingredient the source names without specifying
- a yield the source omits, since the front columns are what a cook provisions from

Silently resolve everything else. An obvious typo gets fixed and goes unmarked. Consistency is
what makes an unmarked cell mean something.

### 8. Quantities

The **total** and the **increment** answer different questions and are both required.

A cook checking stock asks *do I have enough, and what do I buy*: that wants the total across the
whole recipe, in the unit the thing is stored or sold in. A cook mid-operation asks *how much goes
in now*: that wants this operation's increment. Most ingredients are used once, so the two numbers
coincide and the distinction is invisible. It appears the moment an ingredient is used twice.

Where an ingredient enters at two points, give each row its increment and add the total to the
first. **The increments sum to the total** — the one arithmetic check the sheet supports.

Choose one measurement basis per ingredient by what the ingredient demands: grams where precision
carries the result, volume or count where it does not. Where the source offers several — *1 stick
plus 3 tablespoons; 11 tablespoons; 5½ ounces; 155 grams* — take the one that carries the result
as the amount and keep at most one other as the buying unit. Four expressions of one quantity is
the source hedging, and the sheet decides. The mixed basis is itself information —
`220 g flour` beside `2 carrots` shows where the tolerance is at no cost. Add a buying unit,
muted, where it differs usefully from the working amount, and treat it as the first thing on the
sheet to go stale.

### 9. Self-check

Every line, before you emit anything.

- [ ] Every ingredient from the source appears, quantity intact.
- [ ] Every operation appears, or sits in the Prep column under the arity gate.
- [ ] Every Prep cell holds one ingredient's own work.
- [ ] Every node's rows are contiguous.
- [ ] Grid complete: every position covered exactly once, colspans summing to full width in every
      row.
- [ ] One cell in the rightmost column of the last stage.
- [ ] Every cell shows its operands by extent alone.
- [ ] Every stage passes the fit test at `LAYOUT.md`: the table fits 43 lines once rows stretch,
      and every column clears its longest word.
- [ ] Every break satisfies the three conditions or says it is forced, and every free block long
      enough to leave the kitchen sits at the foot of a page.
- [ ] Chart framed on all four edges; the rule hierarchy holds.
- [ ] Every stage is under 21 ingredient rows.
- [ ] Padding cells open the block to their right and close it where that block ends.
- [ ] Any quantity split across stages is named in a Shopping band on page one.
- [ ] No footer, no numbered notes, no key.
- [ ] Version date on every page's title line.
- [ ] At most 2 fused notes per page, each 20 words or fewer.
- [ ] Every column clears its longest unbreakable run, non-breaking spaces included.
- [ ] Increments sum to the total on every multi-use ingredient.
- [ ] Every operation has a cue, or is a combining step with no heat and no chemistry.
- [ ] Every leaf has a parent operation; accompaniments sit in the band, not in the grid.
- [ ] Any operation running twice over parts of one batch says so, with the count.
- [ ] Every clock is a range.
- [ ] Timing computed, not copied; any conflict with the source stated in the band.
- [ ] Every irreversible failure sits in its operation cell.
- [ ] Every marked inference passes a trigger in step 7; every unmarked resolution is one a cook
      would not want to revisit.
- [ ] Bands hold only what is true before the knife comes out.
- [ ] A target state line is present.
- [ ] Version date present.
- [ ] Every degraded DAG edge is recorded.

Then the real test. **From the sheet alone**, can a cook answer: what do I buy? what do I have
enough of? what do I chop before I start? what goes in the same pan? what can I do while something
else runs? how long until dinner? what should it look like when it's right? what do I do if it
isn't? Each question that sends them back to the original is a missing field.

## Degrading a DAG

The grid draws a tree. Where the graph is not one, the model keeps the truth and the rendering
records what it dropped.

An intermediate feeding two operations, and one operation yielding two products — searing gives
meat *and* the fond, straining gives solids *and* liquid — both exceed what a cell can show. Keep
the larger part of the dish in the chain, start the other as a fresh branch whose first row is
what joins it, and **say in the cell that the two share a vessel**: `deglaze the fond the sausages
left`. The link then lives at the step that needs it. A row is for something you measure out, so
fond gets no row of its own.

Emit the list of degraded edges after the sheet. Emit nothing else of the graph.

## When to reach for more

- Building the graph, field by field → `IR.md`
- Traversal, spans, column geometry, the HTML contract, timing arithmetic → `LAYOUT.md`
- Ties, sub-recipes, batches, delegated steps, layering, optional ingredients, source errors,
  plating → `HARD-CASES.md`
- Three sheets built from real sources, and what each one tests → `EXAMPLES.md`

## Output

1. The sheet, as a self-contained HTML file with no external dependency.
2. The degraded-edge list, if any.
3. Anything the source left open that step 7's triggers did not warrant marking, in one line.

---

**Version 1.2** — 2026-09-08. Derived from first principles, then tested against three real
sources: a skillet stew, a baking recipe that runs on cues rather than clocks, and a set of
shorthand notes. All three are in `EXAMPLES.md`, and every one caught a defect that reasoning
alone had missed. Run a proposed change against all three before accepting it.

v1.2 fixed four more, found when a fresh session ran v1.1 on a three-day cassoulet: no row-count
ceiling, so a seventeen-ingredient session overflowed by half a page; no rule for a tie spanning a
stage break; a word floor that stated a constraint without saying what to do about it; and a
height model that measured row minimums from the whole row instead of the ingredient columns.

v1.1 fixed five defects found when a fresh session ran v1.0 on a mac and cheese recipe: two
guardrails lost to over-eager positive phrasing (no footer, no key), an unstated home for the
version date, an unbounded fused note, a word floor that ignored non-breaking spaces, and a fit
test the agent estimated instead of computing.

*The graph-on-a-grid idea is owed to Michael Chu's Tabular Recipe Notation at Cooking For
Engineers, which this format took as a starting point and then diverged from. A "patent pending"
notice still appears on cookingforengineers.com; secondary sources report the application lapsed,
but they are interested parties and cite no filing. Treat the status as unresolved.*
