# Hard cases

Reach here when one fires. Most recipes trigger none.

## An ingredient used at two points

Two rows, each carrying its own increment, and the **total** on the first of them. Fidelity beats
compression: one row holding the whole quantity places it all at the first use and is simply
wrong.

Where the second use has no fixed amount — *more seasoning to taste* — write the total as
`1 tsp. + more to taste`. An open total is honest; a made-up one is not.

## A tie that spans a stage break

Garlic split between day one and day two; seasoning added early and again at the end, on
different pages. The rule that the total sits on the first of the tied rows fails here, because
the first row is on page 1 and the cook holding page 3 cannot see it.

Put a **Shopping band on the first page** naming what is split and where the totals live. It
answers the provisioning question in the one place it is actually asked — cold, before anything
starts — and each later page still carries its own increment where it is used.

## An intermediate used twice

The grid cannot draw it. Either duplicate a small branch, or terminate at a named intermediate and
reference the name in the later cell. Record the edge in `degraded_edges` either way.

## One step, two products

Searing gives the meat *and* the fond. Straining gives solids *and* liquid. Separating eggs gives
yolks *and* whites. A cell shows one product.

Keep the larger part of the dish in the chain. Start the other as a fresh branch whose first row
is what joins it — broth for a deglaze, sugar for the whites. Then **say the link in the cell that
needs it**: `deglaze the fond the sausages left`. The cook learns the two branches share a vessel
at the step where that matters.

A row is for something you measure out, and fond is read from the pan.

## One operation run twice over a batch

Two dough logs sliced and baked one sheet at a time. Pancakes ladled in rounds. A single node
carries a `repeat`, and the cell states the count and what waits: *bake one sheet at a time; the
second waits in the fridge*. Drawing two bake nodes would duplicate the whole subtree for an
operation the cook performs identically twice.

Say it in the operation cell. A cook who reaches the end of the sheet and only then learns there
is a second bake has been told too late.

## Sub-recipes

A component with more than about six ingredients of its own becomes a **stage**, not a separate
sheet: its own leaves, its own operations, its output crossing the break as a named intermediate
with a row in the next stage. That keeps one artifact per recipe.

Reconcile the yields. Where the component's output does not match what the rest consumes, say so
on the sheet rather than silently scaling either one.

## Lead time before the first operation

Butter softened two hours, beans soaked overnight, meat salted a day ahead. These carry two
different facts and both are needed:

- *This recipe needs starting the night before* → the **Make ahead** band, because it answers
  "can I make this tonight" before anything is committed.
- *Cover the beans with 2 L cold water, 12 h* → an **operation** in the earliest stage, because
  it has a quantity, a vessel and a stop.

They are not duplicates. A single-operation lead-in stage shares the first page with a rule across
it rather than taking a page of its own.

## Waits inside the cook

Marinades, resting, chilling, proofing: operations whose duration is the parameter, `free: true`.
They dominate the schedule and the Timing and Serve-with bands schedule against them, so they stay
visible.

A wait that needs no decision and has no separate stop folds into the next operation as a
parameter — *slice once cool enough to handle*.

## Steps delegated outside the recipe

*Cook according to package directions* cannot be resolved from the source. Work out an honest
range so the total means something, mark the duration `(not stated)`, and keep the reason in the
cell. An estimate is not a resolution.

## A recipe with no slack

A stir-fry or a custard offers no legal pause once the heat is on. Prep front-loads and the sheet
shows nine things ready before the pan gets hot. That shape is strange because the dish is, and
saying so is the useful thing. If it overflows, break anyway and state on the page that the break
is forced.

## Source errors, and source ambiguity

Different problems.

An **error** has one viable reading. *"Just bake the cookies 1 minute long"* is a typo for
*longer*. Fix it, unmarked, and move on — you are delivering a complete recipe.

An **ambiguity** has two viable readings that give different dishes, and no amount of care
resolves it. *"1 small red, orange, yellow and green bell pepper"* is either four peppers or one
from an assorted pack, a fourfold difference. Choose, mark it `(inferred)`, and name the reading
in the fewest words: `4 peppers, one of each colour`. The sheet carries the reading you chose and the mark; the cook needs to know the number is a
judgment call rather than to relitigate it.

## To taste

Real leaves attached to the operation where they enter. Seasoning added early *and* adjusted at
the end is two tied rows, not one.

## Optional ingredients and variations

Optional ingredients stay as rows marked *(optional)*. Variations go in the Swaps band. Branching
alternatives break contiguity, so the band holds them.

## Layering and plating

Spatial arrangement is the one thing the grid cannot encode at all. Use one `assemble` operation
whose cell states the order in words. Where the order genuinely cannot be said in a cell, the
recipe is asking for a diagram and this format is the wrong tool — say so rather than deforming
the grid.

## Too small to bother

One operation over one undifferentiated set of ingredients is a sentence, not a grid. Say so.
Five ingredients and two operations is already enough for the geometry to pay.
