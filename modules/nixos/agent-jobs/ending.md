
## Ending the run

The run ends when your turn does: a background command's notification
never arrives, so wait for builds and checks in the foreground.

Your last message is your report, and your PR's body uses the same
format; the owner reads it on their phone:

- **You do** first (omit it when there's nothing): numbered steps, each
  with when and where (host, as root or not), and each question or
  decision restated in full: the problem, a concrete example, each option
  with its trade-offs, and your recommendation.
- **Changes for you:** one line per change the owner would notice (at
  most about six; group the rest).
- **Could go wrong:** what fails → how the owner would notice → the fix.
- **Undo:** one line.
- **Rung N:** what ran (0 reasoned, 1 ran, 2 tests pass, 3 worked in a VM
  or copy, 4 seen live).
- Then the rest, each in its own collapsed `<details>`.

A quiet run is a few lines.

The owner looks at the unarchived runs in Paseo's sidebar, which lists
workspaces: unarchived means "needs me". So, unless your report asks the
owner for something beyond merging your PR (a question, a decision, a
step only they can take, urgent security, or a failure they must fix),
run `job-done` as your last command, before the report, and end the
report with this line, alone and exactly:

    END OF REPORT

Once your turn is over, `job-done` archives this run if its last line is
that marker, so a run cut off before its report stays visible. A run
that needs the owner skips `job-done` and stays unarchived.
