# Signs of AI writing -- full reference

Distilled from [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
(retrieved 2026-09-02), an essay maintained by Wikipedia editors to spot
undisclosed LLM-generated edits. Organized here by how general-purpose
the section is: content/language/formatting tells apply to any prose;
the later sections (citations, edit summaries, markup bugs, "signs of
human writing") are specific to Wikipedia's own editing environment and
are here for completeness, not because they generalize.

Word lists shift with model releases -- what was a strong tell for
GPT-4 in 2023 is less distinctive now that later models and RLHF passes
have partly trained it out (e.g. "delve" spiked in 2023-2024 and then
dropped sharply through 2025). Treat specific words as evidence that
decays, and the underlying *patterns* (inflated significance, empty
"-ing" analysis, promotional tone, hedge-laundering, formulaic closers)
as the durable signal.

## Content-level tells

**Undue emphasis on significance, legacy, and broader trends.** Watch
for: "stands/serves as," "is a testament/reminder," "crucial/pivotal/
vital role," "underscores importance," "reflects broader," "symbolizing,"
"contributing to," "setting the stage for," "marking/shaping,"
"represents a shift," "key turning point," "evolving landscape," "focal
point," "indelible mark," "deeply rooted." AI inflates a subject's
importance through generic broader-impact statements -- e.g. describing
a statistical institute's founding as "marking a pivotal moment in the
evolution of regional statistics" rather than just stating what it did.

**Canned emphasis on notability, attribution, media coverage.** Watch
for: "independent coverage," "local/regional/national media outlets,"
"trade publications," "cited/featured/profiled in," "written by a
leading expert," "active social media presence." On Wikipedia this comes
from LLMs echoing the notability guidelines awkwardly -- listing source
*types* rather than substantive content, and attributing analysis to
sources even when the source doesn't support it.

**Superficial analysis tacked onto facts.** Watch for "-ing" phrase
endings: "highlighting," "underscoring," "emphasizing," "ensuring,"
"reflecting," "symbolizing," "contributing," "cultivating," "enhancing,"
plus "valuable insights," "align/resonate with." AI appends an empty
analytical clause to a plain fact without adding real insight, often
framing its own synthesis as if it were the source's attributed
analysis.

**Promotional / advertisement-like language.** Watch for: "boasts a,"
"vibrant," "rich," "profound," "enhancing," "showcasing," "exemplifies,"
"commitment to," "natural beauty," "nestled," "in the heart of,"
"groundbreaking," "renowned," "featuring," "diverse array." Reads like a
travel guide or press release despite an encyclopedic or technical
context; the tell is the *same* small set of positive descriptors
recurring across otherwise-unrelated topics.

**Vague attribution and overgeneralization.** Watch for: "industry
reports," "observers have cited," "experts argue," "some critics argue,"
"several sources/publications," "such as" preceding what's actually an
exhaustive list. Weasel-wording: opinions attributed to vague
authorities, source quantity exaggerated, a single source's view
presented as widespread consensus.

**Outline-like "challenges and future" conclusions.** Watch for:
"Despite its... faces several challenges," "Despite these challenges,"
section headers literally named "Challenges and Legacy" or "Future
Outlook." The formula: "Despite \[positive words\], \[subject\] faces
challenges..." followed by vague, often unsourced speculation about
future initiatives -- recognizable because it appears near-identically
across unrelated articles.

**Leads that treat the title as a proper noun to define.** "**Catchment
area (health)** refers to..." instead of naturally introducing the
concept in a sentence that isn't structurally "term, in bold, refers
to..."

**"Awards and Recognition" as a reflexive section header.** Appears
ubiquitously in AI-written articles regardless of whether the subject
has any awards worth a dedicated section -- a symptom of the broader
"legacy/notability" fixation above rather than genuine content planning.

## Language and grammar tells

**High density of "AI vocabulary" words.** These shift by model era --
useful as a snapshot, not a permanent list:

- *2023 to mid-2024 (GPT-4 era):* additionally, boasts, bolstered,
  crucial, delve, emphasizing, enduring, garner, intricate/intricacies,
  interplay, key, landscape, meticulous/meticulously, pivotal,
  underscore, tapestry, testament, valuable, vibrant.
- *Mid-2024 to mid-2025 (GPT-4o era):* align with, bolstered, crucial,
  emphasizing, enhance, enduring, fostering, highlighting, pivotal,
  showcasing, underscore, vibrant.
- *Mid-2025 onward (GPT-5 era):* emphasizing, enhance, highlighting,
  showcasing, plus the notability/attribution terms above. ("Delve"
  specifically dropped off sharply in 2025 after being the single most
  notorious 2023-2024 marker.)

Any one of these words is nothing on its own; several co-occurring in
the same paragraph is the actual signal.

**Avoidance of plain "is"/"are."** AI frequently substitutes: "serves as
a," "stands as," "marks," "functions as," "operates as," "represents,"
"boasts," "features," "maintains," "offers." Example: "Gallery 825
serves as LAAA's exhibition space" where a human editor would more
likely write "Gallery 825 is LAAA's exhibition space."

**Vague expression of connection.** Watch for: "in connection with,"
"connected with/to," "in association with," "associated with," used as
an indirect abstraction rather than a precise preposition -- e.g. "in
connection with environmental award recognition" instead of just "for
environmental awards."

**Negative parallelisms.**

- *"Not just X, but also Y":* "not only dismissive but also
  unnecessarily harsh," "not just undermine... it questions," "it is not
  just a meme -- it's a celebration."
- *"Not X, but Y":* "it's not grounded in visual mastery, but in
  performative enactment," "not a representation of self, but a
  mechanism."

AI frames plain statements as if correcting a misconception the reader
never had. Common, but less distinctive on its own than the vocabulary
and phrase-pattern tells above.

**Rule of three.** Reflexive triplets of near-synonymous adjectives or
clauses where a single specific word would carry the same information
with less padding.

## Style and formatting tells

- **Title heading** -- an unnecessary top-level section header that
  just restates the article/document title.
- **Title Case** used where normal sentence case is standard.
- **Headings that contain only more headings** -- structural bloat with
  no actual prose under a heading before the next subheading starts.
- **Overuse of boldface** for emphasis well beyond what the content
  needs.
- **Inline-header vertical lists** -- every bullet led by a bolded
  "Label:" fragment, turned into a de facto table without using one.
- **Overuse of em dashes** replacing commas, parentheses, or periods
  throughout a piece.
- **Emoji used as formatting** -- section dividers or bullet markers
  rather than actual content.
- **Unusual use of tables** for content that reads better as prose.
- **Curly ("smart") quotation marks and apostrophes** where the
  surrounding text/platform convention uses straight ones -- a
  formatting inconsistency characteristic of certain LLM output
  pipelines.
- **Skipping heading levels** -- jumping from H2 straight to H4.
- **Overuse of level-1 headings** where a document should mostly live
  under one H1 with H2/H3 substructure.
- **Unnecessary thematic breaks** (horizontal rules) between ordinary
  sections that don't need one.

## Communication and markup tells (Wikipedia-specific)

- **Collaborative/peer address** -- "let's," "we," language that treats
  the reader as a dialogue partner rather than an encyclopedia audience.
- **Knowledge-cutoff disclaimers** -- stray statements about the
  model's training-data limitations or speculation about source gaps,
  left in by accident.
- **Phrasal templates and placeholder text** -- generic scaffolding
  wording left in the final output.
- **Markdown syntax** left in place of Wikipedia's own wikitext markup.
- **Broken wikitext** -- malformed Wikipedia-specific formatting.
- **Internal formatting/reference markup bugs**, i.e. leaked
  tool-call/citation artifacts specific to a given assistant:
  - ChatGPT: `contentReference`, `oaicite`, `oai_citation`, `+1`,
    `turn0search0`, `attributableIndex`.
  - Gemini: `[cite: 1]`, `[span_1](start_span)`.
  - Grok: `grok_card`, `grok_render_citation_card_json`.
  - DeepSeek: lenticular brackets, dagger symbols.
  - Perplexity: `attached_file`, `ppl-ai-file-upload`.
  - Unclassified: `:::writing`.
- **Non-existent or out-of-place categories**, and **non-existent
  templates** -- invalid Wikipedia markup an LLM hallucinated as if it
  were real.

## Citation tells (Wikipedia-specific)

- Broken external links (non-functional URLs in references).
- Invalid or malformed DOIs and ISBNs.
- DOIs that resolve to an unrelated article.
- Book citations missing page numbers or URLs.
- Incorrect or unconventional reference formatting/use.
- `utm_source=` tracking parameters left in cited URLs.
- Named references declared (`<ref name=...>`) but never actually cited
  in the article body.

## Edit summary tells (Wikipedia-specific)

- Generic LLM-style summaries that claim a "neutral" rewrite while the
  diff actually introduces promotional tone.
- Canned policy-adherence assurances: "Preserved adherence to Wikipedia
  policies," "Ensured compliance with guidelines."
- Procedural framing ("preserved/retained information," "avoided
  mistakes") that talks about editing *process* rather than content
  substance.
- Overemphasis on citation presence/reliability, or on markup/parameter
  names, as the summary's main content.
- Stray references to the Articles for Creation (AfC) review process.

## Other Wikipedia-specific indicators

- A pronounced, abrupt shift in writing style partway through one
  article.
- "Submission statement"-style meta-commentary in AfC drafts, explaining
  the edit the way an assistant explains its own actions.
- Maintenance templates pre-placed prophylactically, before they're
  actually warranted.
- Generic, template-like user pages with boilerplate biographical
  scaffolding.
- "Permissions gaming" -- structuring contributions strategically around
  Wikipedia policy to get AI-assisted content through review.
- Per-model quirks: e.g. Grok over-uses "causal," "empirical,"
  "correlate," and kept using "underscore" into 2026 after other models
  had mostly dropped it.
- A documented pro-authoritarian bias: some models present authoritarian
  framings uncritically or over-represent positive state-aligned
  narratives when summarizing politically sensitive topics.

## Signs of human writing (for calibration, not proof)

- **Age relative to ChatGPT's launch (November 2022).** Text
  demonstrably predating widely-accessible LLM chatbots is contextual
  evidence of human authorship, not proof by itself.
- **Ability to explain editorial choices.** A human author can usually
  articulate *why* they made a specific wording or structural choice;
  AI-assisted contributors often can't produce a coherent account of
  their own edit's reasoning when asked.
- **Varied syntax.** Human writing tends to show more sentence-structure
  variation; consistent, repetitive sentence patterns lean the other
  way -- though this is a weak signal on its own.

## Historical / now-unreliable markers

Kept for context -- these were real tells for early ChatGPT (roughly
November 2022 to 2024) but have since disappeared as models improved,
so treat them as noise now rather than evidence:

- Didactic disclaimers ("As an AI language model...") -- pedagogical
  framing from early ChatGPT, gone from later versions.
- Section-summary recap paragraphs at the end of every section -- now
  less common.
- Explicit prompt refusals leaking into output.
- Abrupt mid-sentence cut-offs from early context-length failures.
- Suspiciously uniform/outdated access-date parameters in citations,
  suggesting automated scraping.
- Excessive "elegant variation" (over-synonymizing to avoid word
  repetition) -- early models over-did this; later models mostly don't.
