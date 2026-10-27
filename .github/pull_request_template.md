<!-- Every PR fills For, Doesn't do and New parts. Keep the headings. -->

## For

<!-- What this change is for: the owner's request, the TODO.md item or the requirement it serves. -->

## Doesn't do

<!-- What it deliberately leaves out, one line. "Nothing beyond the purpose" is fine for a one-sentence change. -->

## New parts

<!-- Each service, timer, job, check, process or rule this adds, one line each, with the requirement it serves. A part carried from the old tree cites its step 2 verdict (carry-list row). Or "none". -->

## Consequential

<!-- "yes, because ..." or "no, because ...". Yes when it deletes or exposes data, touches secrets, public exposure, the agents' boundary, instructions or skills, or the deploy machinery, or adds a new part (policy C1). -->

## What you'd notice

<!-- Consequential only: what the owner would notice, where and when. -->

## Undo

<!-- Consequential only: how to undo it. A stateful step: "no undo, verified copy at <where>". A secrets step: "revert before revocation; after it, no undo: regenerate". -->

<!-- A fix-forward of a merged PR: add a line "Fixes: #N". -->
