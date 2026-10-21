---
name: important-question
description: Use when the user says "important question", or asks for an answer checked by both Claude and Codex. A Claude subagent and Codex each answer the question independently, in parallel, and the main thread merges the two reports into one answer, labelling each claim by who made it and putting conflicts first.
---

# Important question

The point is two independent answers from two model families. You merge
them; you don't research the question yourself, so you have no side.
Only the user starts this; don't suggest it.

## 1. Write the question once

Write one prompt and send it, word for word, to both researchers. Include
any facts from the conversation the question depends on, but not your own
view, earlier notes or a draft answer: anything both read, both inherit.
End the prompt with:

> Research this independently, using web search. Give a direct answer
> first, then the supporting points. Cite a URL for every factual claim,
> say how confident you are, and say what you couldn't verify. Keep it
> under 800 words.

## 2. Run both in parallel, in one turn

- **Claude:** a `general-purpose` subagent with the prompt.
- **Codex:** in the background,
  `codex --search exec --skip-git-repo-check --ephemeral -C ~/work/scratch -o <file> "<prompt>" < /dev/null`.
  The answer is in `<file>`. Delete the file once you've merged.

If you are Codex, swap them: your own subagent, and
`claude -p --permission-mode bypassPermissions "<prompt>" < /dev/null`
for Claude.

If either fails, say so and give the other's answer, marked as
single-source. Don't pass one report off as a merge.

## 3. Merge into one answer

Treat the reports as equals; don't favour the one from your own model
family. The claims only one of them made, and the conflicts, are what
the user is paying for, so never drop them to make the answer tidier.

- **Conflicts first.** Each one with both sides and their sources. You
  may say which side is better sourced, but the user decides.
- **Then the answer**, with each claim labelled **[both]**, **[Claude]**
  or **[Codex]**.
- Write for a phone screen: short sections, no wide tables.
