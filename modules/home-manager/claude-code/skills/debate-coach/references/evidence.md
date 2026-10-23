# Evidence behind the persuasion principles

Strength: **R** replicated or meta-analytic · **S** single study or research group · **C** contested · **F** folk wisdom, untested. "(abstract)" means only the abstract was read.

## Contents
- What changes minds: evidence (AI dialogue trials)
- r/ChangeMyView field data
- Human conversation methods (deep canvassing, street epistemology, motivational interviewing, listening)
- Backfire effect
- Identity, moral reframing, receptiveness
- Message design, concessions, confidence
- Failure modes
- Truth-seeking tools
- Where the evidence is thin

## What changes minds: evidence

- **Costello, Pennycook & Rand 2024, *Science*** (R). About three rounds of GPT-4 dialogue, each tailored to a conspiracy the participant described in their own words, cut belief by about 20% (d = 1.15). The effect lasted 2 months, spilled over to unrelated conspiracies, and didn't touch true ones. 99.2% of the claims checked were accurate. DOI 10.1126/science.adq1814
- **Costello et al. 2025, "Just the facts"** (S, preregistered). The effect survived being told it was an AI trying to persuade, a debate framing, concise output and a single static message. **Only removing the facts killed it.** People who changed their minds credited the factual arguments. https://osf.io/preprints/psyarxiv/h7n8u_v1
- **Lin et al. 2025, *Nature*** (R; elections in three countries). Banning facts and evidence cut the persuasion effect by 50–78%. Personalization made no difference. https://doi.org/10.1038/s41586-025-09771-9
- **Hackenburg, Tappin et al. 2025** (R, N = 76,977, 19 models).
  - An information-focused prompt beat "be persuasive" by 27%. Moral-reframing and deep-canvassing prompts did *worse*.
  - Information density explained 44% of the variance in persuasion; personalization added under 1 point.
  - Conversation beat a static message by 41–52%.
  - **The tradeoff:** the levers that raised persuasiveness lowered accuracy (GPT-4o fell from 78% to 62% accurate).
  - https://arxiv.org/abs/2507.13919
- **Salvi et al. 2025, *Nature Human Behaviour*** (S). In short debates, GPT-4 given demographics beat humans 64% of the time; without them it was no better than humans. The effect wasn't significant on topics people felt strongly about. https://arxiv.org/abs/2403.14380
- **Anthropic 2024** (S). Of the argument strategies tested, the *deceptive* one persuaded most, plausibly because readers don't check. https://www.anthropic.com/research/measuring-model-persuasiveness
- **Zurich r/CMV bot experiment, 2024–25.** Unpublished and ethically compromised: undisclosed bots, invented identities, personalization from scraped post histories. Its claimed results are worth little as evidence. It's a cautionary example of fabricated lived experience.

## r/ChangeMyView field data

**Tan et al. 2016, "Winning Arguments"** (S, large dataset, correlational). https://arxiv.org/abs/1602.01103
- Early entrants were about 3x more likely to win a delta than the 10th challenger.
- Odds peak early; after 5 rounds of back-and-forth the challenger had almost no chance, and nobody won with 6+ replies.
- The strongest signal: winning replies brought *new content words* rather than echoing the OP.
- Links to evidence, examples, hedges and calm language helped. "It hurts to be too intense."
- Length correlated with winning, but as a stand-in for content; padding doesn't help.
- Persuadability was barely predictable. OPs writing in "I" were more malleable than those writing in "we".
- **Follow-up:** winners more often addressed the OP's specific "vulnerable" sentences (Jo et al. 2018, abstract). https://aclanthology.org/N18-1010/

## Human conversation methods

- **Deep canvassing** (R, small effects).
  - Kalla & Broockman 2020, *APSR*: on exclusionary attitudes, **arguments alone had no effect**. Adding a non-judgmental exchange of narratives reduced them for 4+ months (d ≈ 0.04–0.08).
  - Kalla & Broockman 2023: "perspective-getting" (hearing the out-group's experience) is enough on its own.
  - https://www.cambridge.org/core/journals/american-political-science-review/article/abs/reducing-exclusionary-attitudes-through-interpersonal-conversation-evidence-from-three-field-experiments/4AA5B97806A4CAFBAB0651F5DAD8F223
- **Matching method to disagreement:** the trials where facts won were on factual and policy beliefs; the narrative trials were on prejudice. Use evidence for the former and listening for the latter.
- **Street epistemology** (S). Reflection prompts and an AI street epistemologist cut conspiracy belief about 0.5–0.7 points on an 11-point scale, with no effect on people who rated accuracy as extremely important. Probably smaller than evidence dialogues. https://misinforeview.hks.harvard.edu/article/using-an-ai-powered-street-epistemologist-chatbot-and-reflection-tasks-to-diminish-conspiracy-theory-beliefs
- **Motivational interviewing** (R for vaccines only). In an RCT, MI by midwives cut vaccine hesitancy by about 10/100 points at 7 months. Untested on contested political beliefs.
- **High-quality listening** (S, lab). Being listened to reduced attitude extremity and made speakers more aware of their own inconsistencies (Itzchakov, Kluger & Castro 2017).

## Backfire effect

- **Wood & Porter 2019** (R): 52 issues, more than 10,000 people, no correction triggered backfire.
- **Swire-Thompson et al. 2020:** backfire isn't robust and looks like a measurement artifact. Restating the myth inside a clear correction is fine. https://pmc.ncbi.nlm.nih.gov/articles/PMC7462781
- **Coppock, *Persuasion in Parallel*** (23 RCTs): nearly everyone updates a little toward information, and partisans update in parallel.
- **Nyhan 2021, *PNAS*:** corrections work somewhat but fade or get swamped by elite cues. Correcting a fact rarely changes the attitude it supported.

## Identity, moral reframing, receptiveness

- **Moral reframing** (Feinberg & Willer 2015) (C). Framing in the opponent's values helped in the original studies. There's no meta-analysis, it underperformed in Hackenburg, and it works best after listening, not as a trick.
- **Identity-protective cognition** (Kahan) (C). People discount evidence that threatens their group; replications are mixed. The practical upshot still holds: don't make agreeing a betrayal.
- **Conversational receptiveness** (Yeomans, Minson et al. 2020) (S).
  - Acknowledgment, subjectivity ("I think") and hedges made writers seem more persuasive and drew fewer attacks later.
  - People misjudge how receptive they sound.
  - https://www.hks.harvard.edu/publications/conversational-receptiveness-improving-engagement-opposing-views
- **Asking for elaboration** (S, abstract) made counterparts more receptive (Chen, Minson & Tormala 2010).
- **Personal stories** earn respect but weren't shown to persuade (Kubin et al. 2021). https://pmc.ncbi.nlm.nih.gov/articles/PMC8017692

## Message design, concessions, confidence

- **O'Keefe & Hoeken 2021** (R, 1,149 studies). Most design choices barely matter (median r ≈ .10).
  - Held up: amount of evidence (r = .225, the only reliably positive one), argument strength (.19), explicit conclusions (.14).
  - Didn't: language intensity (.02) and narrative vs statistics (.04).
  - https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.664160/pdf
- **Two-sided messages** (R). Overall ≈ 0, but acknowledging the other side *and refuting it* beats one-sided, while acknowledging without refuting is worse. This matters more when the listener's attitude is strong or moral (Xu & Petty 2022, abstract).
- **Concessions and admitted error** can raise persuasion, especially from experts (Hussein & Tormala 2021 review). https://www.gsb.stanford.edu/faculty-research/publications/undermining-your-case-enhance-your-impact-framework-understanding
- **Calibration:**
  - A confident source who turns out wrong loses more credibility than a hesitant one (Tenney et al. 2007).
  - Ranges and probabilities aren't penalized; "not sure" is (Gaertig & Simmons 2018).
  - Stating numerical uncertainty costs little trust (van der Bles et al. 2020).

## Failure modes

- **Gish gallop / piling on** (F). There's no direct test. The "presenter's paradox" (abstract) found that mildly favorable add-ons dilute strong points, because evaluators average.
  - **Reconciling with the density finding:** many strong, relevant claims help; filler hurts.
- **Interrogation / burden-shifting Socratic questioning** (F).
  - Controlling, freedom-threatening language raises reactance, which works against persuasion (meta-analytic r ≈ .20).
  - Making people explain how a policy works failed to moderate them on replication (Crawford & Ruscio 2021).
- **Incivility** polarizes readers (Anderson et al. 2014) (S). Specific evidence on condescension is folk wisdom.
- **Steelmanning / Rapoport's rules** (F, untested directly). The nearest support is the receptiveness and refutational two-sided findings.

## Truth-seeking tools

- **Argument mapping** improves critical thinking (moderate effects; mostly reported by its proponents).
- **Double crux** (F). A single shared crux is often rare, since beliefs rest on many considerations. Use "cruxes", plural.
- **Empirical vs value layers** (S, abstract). People adjust their beliefs about consequences to fit their moral verdicts (Liu & Ditto 2013), so label which layer each claim is on.
- **Verification:**
  - Persuasion pressure lowers model accuracy (Hackenburg).
  - Older models fabricated many citations (GPT-3.5 55%, GPT-4 18%; Walters & Wilder 2023, abstract).
  - Assistants are sycophantic toward the user's view (https://arxiv.org/abs/2310.13548).
  - Hence: open every source, and be willing to tell the user they're wrong.

## Where the evidence is thin

- **Who was studied:** almost everything is crowdworkers, single sessions and self-reported scales.
- **Opponents:** nothing tests a human using AI-prepared notes against an engaged, hostile opponent.
- **Settings:** nothing covers live or voice debate, or onlookers versus the target in a public thread.
- **Untested techniques:** street epistemology, MI on political beliefs, double crux and steelmanning are mostly untested. Moral reframing is contested.
