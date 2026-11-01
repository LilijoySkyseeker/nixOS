---
name: important-question
description: Use when the user says "important question", or asks for an answer checked by several agents or model families. The user names the agents to ask; each answers the question independently, in parallel, and you merge their reports into one answer, labelling each claim by who made it and putting conflicts first.
---

# Important question

The point is independent answers from the agents the user picked. You
merge them; you don't research the question yourself, so you have no side.
Only the user starts this; don't suggest it.

## 1. Call the agents the user named

The user names the answerers with the question. Call exactly those: don't
add one, drop one or swap one for another. If they named none, ask which
before you start, listing these:

- **Claude:** a `general-purpose` subagent if you are Claude, else
  `claude -p --permission-mode bypassPermissions "<prompt>" < /dev/null`.
- **Codex:** your own subagent if you are Codex, else
  `codex --search exec --skip-git-repo-check --ephemeral -C ~/work/scratch -o <file> "<prompt>" < /dev/null`
  (the answer is in `<file>`; delete it once you've merged).

The local model only when the user names it ("local", "Qwen"): naming it
overrides the rule against using it for opinions. Its command is in the
`other-agents` skill; its model name and whether its server is up are in
`local-ai`. Don't offer it when asking which agents to use.

## 2. Write the question once

Write one prompt and send it, word for word, to every answerer. Include
any facts from the conversation the question depends on, but not your own
view, earlier notes or a draft answer: anything all of them read, all of
them inherit. End the prompt with:

> Research this independently, using web search (or `web-fetch` and curl
> if you have no search tool). Give a direct answer first, then the
> supporting points. Cite a URL for every factual claim, say how confident
> you are, and say what you couldn't verify. Keep it under 800 words.

## 3. Run them in parallel, in one turn

Start every answerer in the same turn, in the background where you can. If
one fails or times out, say so and merge the rest, naming who's missing.

## 4. Merge into one answer

Treat the reports as equals; don't favour the one from your own model
family. The claims only one of them made, and the conflicts, are what
the user is paying for, so never drop them to make the answer tidier.

- **Conflicts first.** Each one with every side and its sources. You may
  say which side is better sourced, but the user decides.
- **Then the answer**, with each claim labelled by who made it:
  **[all]**, or the names, such as **[Claude]**.
- Write for a phone screen: short sections, no wide tables.
