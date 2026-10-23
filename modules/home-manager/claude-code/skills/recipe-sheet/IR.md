# The graph

Build this in full before drawing anything. It is a **DAG**: model what is true, and let the
rendering record what a grid cannot draw.

```json
{
  "title": "Sausage, Peppers and Onions with Beans",
  "yield": "4–6 servings",
  "source": "Deep South Dish, 2015",
  "locator": "https://…",
  "version": "2026-09-07",
  "target_state": "Thick and glossy, beans holding their shape, liquid coating a spoon.",
  "bands": {
    "equipment": ["large skillet", "grill or second pan", "colander", "can opener"],
    "timing": {"hands_on": [16, 20], "free": [20, 25], "elapsed": [42, 55],
               "source_claim": 40, "conflict": true},
    "appliance": null,
    "make_ahead": null,
    "swaps": ["Sausage: chicken or turkey Italian, andouille, smoked, or good hot dogs"],
    "serve_with": ["Cornbread or rolls", "over rice"]
  },
  "nodes": [
    {"id": "i1", "kind": "ingredient", "name": "Italian sausage",
     "amount": "1 lb. pkg.", "total": null, "buying": null, "prep": null},

    {"id": "i13", "kind": "ingredient", "name": "Italian seasoning",
     "amount": "1 tsp.", "total": "1 tsp. + more to taste", "buying": null,
     "prep": null, "tied_to": ["i15"]},

    {"id": "o1", "kind": "operation", "verb": "brown the sausage",
     "params": "package time governs", "vessel": "grill or 2nd pan",
     "cue": "browned through and cooked to the package's temperature",
     "duration": [8, 12], "free": false,
     "inferred": "duration", "precision": null,
     "produces": null, "operands": ["i1"]},

    {"id": "o6", "kind": "operation",
     "verb": "add sausage, boil, then simmer uncovered",
     "params": "20–25 min., low, stirring often",
     "cue": "reduced and thickened, coating a spoon",
     "duration": [20, 25], "free": true,
     "produces": null, "operands": ["o5", "o2"]}
  ],
  "root": "o7",
  "degraded_edges": [],
  "stages": [{"nodes": ["o1", "…"], "break_after": null, "forced": false}]
}
```

## Fields

**`amount`** is this row's **increment** — what goes in at this point. **`total`** is filled only
when the ingredient enters at more than one point, and then it appears on the first of the tied
rows. The increments sum to the total. Where an ingredient is used once, `total` stays null
because the increment already is the total.

**`buying`** carries the purchase unit when it differs usefully from the working amount — a bag,
a can size, a bottle. It describes the shop rather than the dish, so it ages fastest of anything
on the sheet.

**`amount`** may be absent. *Lemon juice*, *salt and pepper*, *a pinch*, *to taste* are all
normal.

**`prep`** holds one ingredient's own unary, any-time work. Anything combining two ingredients is
an operation no matter how far ahead it could be done.

**`cue`** is the stop condition and every operation has one. Keep it out of `params`. Where the
clock genuinely governs instead — a timed brine, minutes under pressure — the cue says so.

**`duration`** is `[low, high]`. One number from the source fills both. No number from the source
means you work out an honest range: wide where the step really varies, narrow where it does not.
Browning five sausages is 8–12 minutes. A pressure release is 2 minutes quick or 15–20 natural, so
carry both rather than averaging into a number describing neither.

**`free`** is true when the cook's attention is released for the duration. This drives the one
visual mark and it is what the Timing and Serve-with bands schedule against.

**`inferred`** names the field you decided rather than read, and only where the other reading
materially changes the dish. Everything else you resolve silently.

**`precision`** names a field where deviation breaks the result.

**`produces`** names an intermediate when a second one exists at the same time, and always when
one crosses a stage break.

**`operands`** is **ordered**, and that order becomes row order. Put the branch that starts
earliest in real time first.

**`repeat`** names the portion an operation is applied to, when it runs more than once over parts
of one batch — two logs sliced and baked one sheet at a time, pancakes ladled in batches. One node
carries it; the cell states the count and what waits. Without this field the graph claims a single
bake where the kitchen does two.

**An ingredient only reaches the graph if an operation consumes it.** An accompaniment — rice
beside a stew, bread for sopping — has no parent, so it cannot own a row and cannot be drawn. It
goes in the Serve-with band with the point in the timeline where it starts. A dangling leaf is
how you find one: the traversal will not place it.

One row may name several ingredients that always travel together and enter at the same point —
*kosher salt, cracked black pepper*. Use it sparingly.

## Invariants

- Exactly one root. Everything reachable. No cycles.
- Every ingredient in the source is a leaf in the graph.
- Every operation has exactly one `cue`.
- Every operation has at least one operand, **except an appliance step** — preheating an oven,
  lining sheets, bringing a pot to pressure. These consume nothing and produce no intermediate.
  They belong in the appliance band with the free block they fit inside, not in the grid.
- Every tied ingredient's increments sum to its `total`.
- `degraded_edges` records every DAG edge the tree rendering could not draw, with the operation
  that carries the plain-language link in its cell.

Build it, do not emit it. The only part that surfaces is `degraded_edges`.
