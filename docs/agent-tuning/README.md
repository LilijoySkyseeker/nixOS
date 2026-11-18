# Agent tuning memory

`memory.json` records every change made to the agents' shared instructions
and skills to cut down how often the owner has to step in, after
Self-Improvement Memory (arXiv:2611.18856). Each problem collects its
attempts. Each attempt records what changed and why, a prediction written
before it ships, and later what was observed, per model family. Attempts
that failed or were reverted stay in the file.

- **Measure:** babysitting messages per 100 owner messages, counted from
  saved sessions. Babysitting means the owner corrects a mistake, repeats a
  rule, redoes or undoes work, approves something the agent should have
  decided, or chases unfinished work.
- **Statuses:** `proposed` (in an open PR), `live` (merged; the date it
  merged starts the observation window), `held`, `partial`, `failed`,
  `reverted`.
- **Privacy:** only counts, causes and predictions go here; the repo is
  public. The owner's messages and session IDs stay in
  `~/work/projects/agent-tuning/`.
