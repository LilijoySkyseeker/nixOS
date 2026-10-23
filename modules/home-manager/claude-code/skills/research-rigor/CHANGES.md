# Changes from the previous research-rigor

Not needed at runtime; kept for the maintainer.

- **Structure.** Reorganized from a catalog of failure statistics into a research workflow with a short pre-send check. Statistics moved to references/evidence.md so SKILL.md stays short.
- **Sourcing.** Most figures in the old SKILL.md had no source in the skill. All of them are now traced to primary sources, with these corrections:
  - "~74% citation accuracy" is 74.5% citation precision, and comes from Liu et al. 2023, not CiteFix.
  - "Citation volume is inversely related to reliability" overstated Rao et al., who observed it but ran no formal test.
  - "Medicine is the worst domain" holds for one model only.
  - The 403/429 finding now separates blocked from live pages.
  - The old "matching tokens" wording for Wallat et al. was accurate (planted statements averaged 2-4 tokens) and is kept.
- **Verification.** Added: verify with outside evidence rather than rereading, and check claims apart from the draft (CRITIC, Huang et al., CoVe).
- **Framing.** Added: premise checking, and restating assertions as questions (FreshLLMs, Ask Don't Tell).
- **New coverage.** A fallback for when no search tools work, and a clarification that vendor pages are primary only for their own specs and prices.
- **Migrated from the user's old system prompt:** non-English primary sources and US price localization.
- **Dropped "lost in the middle."** It measures how models read long context, not how people read answers. "Lead with the answer" stays as a style rule.
- **Dropped "No answer beats a wrong one."** It contradicted the calibration rule: a labeled estimate beats silence.
- **Description.** Keeps a broad trigger list but drops the all-caps and "err toward triggering" language. In practice skills load only for tasks substantial enough to need them, so trivial lookups rely on the model's defaults.
