# Evidence behind research-rigor

Each rule in SKILL.md, the finding that motivates it, and how strong that finding is. Every source listed here was opened and checked in September 2026. "Preprint" means not peer-reviewed. Figures are paraphrased; check the paper before quoting one.

## Contents
- Citation integrity
- Writing from sources (decoration)
- Verification
- Search strategy
- Framing and sycophancy
- Source quality
- Numbers
- Source-versus-memory conflicts
- Where to spend extra effort
- Confidence and abstention
- Prompt injection
- Known gaps in this evidence

## Citation integrity

- **Fabricated and dead URLs persist even with live search.** Rao, Wong, Callison-Burch (2026), "Detecting and Correcting Reference Hallucinations in Commercial LLMs and Deep Research Agents", arXiv:2604.03173. Preprint.
  - Scope: 10 models, 53,090 URLs.
  - 3-13% of URLs were "hallucinated", 5.4-18.5% didn't resolve.
  - Deep-research agents did worse than search-augmented chat: 10.7% vs 4.8% hallucinated.
  - Caveat: "hallucinated" is a proxy (doesn't resolve and has no Wayback snapshot), not proof the page never existed.
- **Blocked is not dead.** Same paper, Appendix A, headless-browser recheck of URLs a simple checker couldn't classify:
  - 403s (n=383): 99.7% not dead, of which 83.8% were access-blocked and 15.9% fully live. Concentrated on academic publishers.
  - 429s (n=110): 99.1% live, just rate-limited. Mostly Reddit.
- **More URLs did not mean better URLs.** Same paper: the system emitting the most URLs (113.1 per query) had the highest hallucination rate (13.3%). The authors say volume may worsen per-citation quality but ran no formal test.
- **A failed check must change the answer.** Same paper: in preliminary runs, gpt-5-nano with a URL-checking tool kept re-proposing flagged URLs across up to 14 correction rounds. This is one small model in a preliminary run.
- **Only about half of generated sentences are fully supported by their citations.** Liu, Zhang, Liang (2023), "Evaluating Verifiability in Generative Search Engines", Findings of EMNLP. Peer-reviewed. Across four 2023 engines: 51.5% citation recall, 74.5% citation precision.
- **Citations drift across turns.** Seetha Ram (2025), "Citation Drift", WASP workshop at ACL. Peer-reviewed workshop paper. Over 5-turn conversations about a fixed paragraph, references mutated or disappeared. Only four LLaMA models were tested.
- **Links rot.** Pew Research Center (2024), "When Online Content Disappears". A quarter of pages from 2013-2023 were gone by October 2023, including 38% of 2013 pages. This is why sources are named, not only linked.

## Writing from sources (decoration)

- Wallat, Heuss, de Rijke, Anand, "Correctness is not Faithfulness in RAG Attributions", ICTIR 2025 (arXiv:2412.18004). Peer-reviewed.
  - Method: short answer statements (on average 2-4 tokens) were planted into documents.
  - Command-R+ then cited those documents 57% of the time when they were relevant but previously uncited, and 12% of the time when they were random.
  - The model generates first and attaches a matching source afterward (post-rationalization). This was one model on Natural Questions.

## Verification

- **Checking against outside evidence works.** Gou et al., "CRITIC", ICLR 2024. Peer-reviewed. ChatGPT critiquing its answers with search gained about 10 F1 points on AmbigNQ and HotpotQA; the same critique without search gained about 3.
- **Rereading without new evidence doesn't work.** Huang et al. (Google DeepMind), "Large Language Models Cannot Self-Correct Reasoning Yet", ICLR 2024. Peer-reviewed. GPT-3.5 self-correcting with no outside feedback often changed correct answers to wrong ones; CommonSenseQA fell from 75.8% to 38.1%.
- **Verify apart from the draft.** Dhuliawala et al. (Meta), "Chain-of-Verification", arXiv:2309.11495. Answering verification questions without the draft in context beat checking next to it, because the model can't copy its own earlier errors. Llama 65B biography FActScore went from 55.9 to 71.4 in the best variant.
- **Check per claim.** Wei et al. (Google DeepMind), "Long-form factuality" (SAFE), arXiv:2403.18802. Splitting an answer into single facts and searching each one agreed with human annotators on 72% of facts, and was right in 76% of the sampled disagreements.

## Search strategy

- **Broad then narrow; watch for SEO sources; scale effort.** Anthropic (2025), "How we built our multi-agent research system". Vendor self-report on internal evals. Failures they observed:
  - agents preferred SEO content farms over authoritative, lower-ranked sources
  - overly long, specific queries returned little
  - agents searched endlessly for nonexistent sources
  - agents kept searching after they had enough
  - simple questions were over-resourced
  - Their effort guide: simple fact-finding takes about 3-10 tool calls; comparisons use 2-4 subagents with 10-15 calls each. These are multi-agent budgets, so SKILL.md gives no fixed call count for single-agent work.
- **Search again as reasoning proceeds.** Trivedi et al., "IRCoT", ACL 2023. Peer-reviewed. Interleaving retrieval with reasoning steps improved retrieval by up to 21 points and QA by up to 15 on multi-hop benchmarks.
- **More sources help; premises and fast-changing facts are hard.** Vu et al. (Google), "FreshLLMs", arXiv:2310.03214.
  - Going from 1 to 10 evidence snippets raised strict accuracy from 61.4% to 75.6%.
  - Every model struggled with false-premise and fast-changing questions.

## Framing and sycophancy

- **Deep research systems give one-sided answers.** Narayanan Venkit et al., "DeepTRACE", ICLR 2026. Peer-reviewed.
  - Deep-research modes gave one-sided answers on 54.7-94.8% of debate queries.
  - GPT-5 Deep Research answered "why ban X" and "why not ban X" with opposite one-sided reports.
  - Unsupported-statement rates ranged from 12.5% to 97.5% depending on the system.
- **Search itself can narrow the evidence.** Sharma, Liao, Xiao, "Generative Echo Chamber?", CHI 2024. Peer-reviewed user study, not an agent study. People issued more confirmatory queries with LLM-powered search.
- **Statements invite more agreement than questions.** Dubois et al. (UK AI Security Institute), "Ask Don't Tell", arXiv:2602.23971. Preprint.
  - Sycophancy is higher for statements than for questions, and rises with the user's expressed certainty.
  - Having the model restate a statement as a question cut sycophancy more than a "don't be sycophantic" instruction did.
  - Tested on GPT-4o, GPT-5, and Sonnet 4.5 in single-turn advice.

## Source quality

- **AI-generated sources get cited.** Allaham, Diakopoulos, "Synthetic Sources?", arXiv:2605.23684. Preprint. About 16% of sources cited by four generative search engines across 712 queries were classified as AI-generated.

## Numbers

- Gao et al., "PAL", ICML 2023: having the model write code that an interpreter runs beat chain-of-thought by 15 points on GSM8K.
- Chen et al., "Program of Thoughts", TMLR 2023: about +12% average over chain-of-thought, including financial QA.
- CRITIC (above): a code interpreter also improved math answers.

## Source-versus-memory conflicts

- Wu, Wu, Zou, "ClashEval", NeurIPS 2024 Datasets & Benchmarks. Peer-reviewed.
  - Models adopted incorrect retrieved content over their own correct prior more than 60% of the time.
  - Adoption was higher when the model's token-level confidence in its first answer was lower, and lower when the injected content was more implausible.

## Where to spend extra effort

- **Rare entities.** Min et al., "FActScore", EMNLP 2023. ChatGPT biography precision fell from about 80% to 16% as entity rarity increased.
- **Popularity bias in recalled references.** Algaba et al., arXiv:2504.02767, Quantitative Science Studies. About 90% of GPT-4o's real generated references were in the top 10% most-cited papers for their field and year.
- **Domains.** Rao et al. above found medicine had the highest non-resolving rate for one model (17.4%, Claude Sonnet 4.5); pooled across models, theology and classics were slightly worse. The humanities and law figures in the previous version came from papers Rao cites (Mugaanyi et al. 2024; Dahl et al. 2024), which were not opened here.

## Confidence and abstention

- **Abstention trades a little accuracy for far fewer errors.** OpenAI blog post "Why language models hallucinate" (2025), accompanying Kalai et al., arXiv:2509.04664 (preprint). Vendor self-report; the figures are in the post, not the paper.
  - On SimpleQA, gpt-5-thinking-mini abstained on 52% of questions and was wrong 26% of the time.
  - o4-mini abstained on 1% and was wrong 75% of the time.
  - Accuracy was similar: 22% vs 24%.
  - The paper's argument: accuracy-only grading rewards guessing over saying "I don't know".
- **Models are overconfident.** Wei et al. (OpenAI), "SimpleQA", arXiv:2411.04368. Models consistently overstate their confidence.
- This supports labeled uncertainty and "not found" over guessing. It does not support refusing whenever unsure: a labeled estimate is still an answer.

## Prompt injection

- Greshake et al. (2023), arXiv:2302.12173: instructions planted in web pages hijacked a search-connected chatbot.
- Debenedetti et al., "AgentDojo", NeurIPS 2024: under attack, GPT-4o's attack success rate was 47.7%.

## Known gaps in this evidence

- **The counter-framed query rule is untested.** No study was found that measures its effect directly. It is inferred from DeepTRACE and the echo-chamber study.
- **The question-reframing rule was measured on other models** (GPT-4o, GPT-5, Sonnet 4.5) in single-turn advice, not in research tasks.
- **Many figures come from older models.** Rates for current models are likely lower, but the failure modes were still present in the 2025-2026 audits.
- **Several key sources are single preprints**, notably Rao et al. and Synthetic Sources. Treat them as directional.
- **Vendor posts** (Anthropic, OpenAI) are self-reports on internal evals.
