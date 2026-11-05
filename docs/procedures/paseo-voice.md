# Voice mode in Paseo (GPT-Live)

Goal: talk with a Paseo session the way ChatGPT voice works: a natural spoken
conversation, with real work handed to the session's agent.

`modules/nixos/paseo/gpt-live.patch`, applied to the daemon and the desktop app,
adds this. The voice button on a session, a new tab or New workspace starts it.
Voice runs only while it is on.

## The store mobile app

It isn't patched, but the voice lives in the daemon, so its voice button reaches
GPT-Live too. This is untested on a phone. From the app's unpatched code:

- Ending voice while the agent works also cancels the agent's work. Don't press
  stop mid-task unless you mean that.
- Spoken lines don't appear in its chat; hand-offs show as ordinary messages.
- The voice button is hidden while the agent works, and a new session can't start
  by voice.
- After a quiet close it still looks like voice is on, and it won't reopen voice
  when the agent finishes.
- The smooth-playback fixes are in the desktop's audio engine only, so audio may
  have gaps.

## Provisioning

1. Create a project API key at https://platform.openai.com/api-keys. On the
   project's budget, turn on **Enforce a hard limit**: every agent runs as `agent`
   and can read the key, so that is the limit on misuse, and without it the budget
   only sends alerts
   ([spend limits](https://developers.openai.com/api/docs/guides/spend-limits)).
2. Add it to the torrent secrets, then deploy:

   ```bash
   sops secrets/torrent.yaml   # add: gpt_live_api_key: <key>
   ```

   Until `gpt_live_api_key` is there, torrent's system does not build: sops-nix
   rejects the missing key. Rotating the key needs no restart; each voice start
   reads the file.

What leaves the machine, whichever agent backs the session, even a local one:
microphone audio, up to 12,000 characters of the thread and 6,000 of earlier voice
conversation at each start, then the agent's answers, the kinds of steps it takes,
and permission tool names.

Only the user's speech can start work: the daemon refuses a hand-off unless
GPT-Live recognised the user's words in the last 20 seconds, and each stretch of
speech allows one, because text the agent read reaches the voice as context. This
checks that the user spoke, not what they said: an instruction hidden in a page the
agent read could still get through if the voice follows it just after the user
speaks. Approving each hand-off would close that, and was turned down because it
breaks the conversation (owner, 2026-11-05).

Voice mode is on unless switched off in Settings > Voice, which also closes a
running session.

Cost: GPT-Live bills about $0.05 per minute while voice is on, plus the hand-off
model (`gpt-6-luna`) and the agent's own usage. Settings > Voice has **Close when
quiet** and **While the agent works**; the default keeps voice open during work,
which keeps billing. Out of credits shows as voice failing to start, or as a
hand-off that never happens, with the error in `~/.paseo/daemon.log`.

## Where things are

- Transcripts: `~/.paseo/voice-transcripts/<agent id>/*.jsonl`, one per voice
  session, kept like chat transcripts (backed up with `/home`). Threads restore
  their spoken lines from them, because provider history doesn't hold them.
- Errors: `grep GPT-Live ~/.paseo/daemon.log`.
- Patch source: `~/work/repos/external/paseo-credits`, worktree
  `paseo-live-0.14`, branch `feat/gpt-live-0.14`, on top of the other Paseo
  patches. Regenerate with
  `git diff feat/claude-credit-fallback-0.14..feat/gpt-live-0.14`.

## Rollback

To turn GPT-Live off, remove `PASEO_GPT_LIVE_API_KEY_FILE` from
`modules/nixos/local-ai.nix`: voice falls back to Paseo's own speech settings. To
remove it entirely, also remove `gpt-live.patch` from that file and from
`modules/home-manager/paseo-desktop.nix`, and the secret from
`hosts/torrent/configuration.nix`.

## Changing the prompts

`scripts/gpt-live-routing-check.ts` in the patch source plays synthesised phrases
into real GPT-Live with a stand-in agent and reports routing, hand-offs and
relaying. It costs real API time; read the transcripts it leaves in
`/tmp/gpt-live-routing-*/` before running it again.
