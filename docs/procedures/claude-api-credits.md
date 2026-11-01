# Claude API credits in Paseo

Goal: Continue ongoing Claude work when subscription usage runs out, without
having to explain the task again.

Out of scope: Automatic switching or purchasing additional credits.

Done when: A subscription-backed Claude conversation resumes through API credits
with its history and working directory intact; billing and return to subscription
after reset are verified; the setup survives a rebuild.

Agreed 2026-11-01. Anthropic's included credits cover self-run Agent SDK usage,
which Paseo uses, but not interactive Claude Code or subscription extra usage.
[Coverage and claiming](https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-ultra-and-team-plans).

## Provisioning

1. Claim the recurring credit in claude.ai Settings > Billing > API credits by
   linking the Console organization. Create a workspace-scoped personal API key
   in that organization at https://platform.claude.com/settings/keys.
2. Keep auto-reload off and no purchased balance in the linked organization.
   Anthropic spends included credits first, then any purchased balance. With no
   other balance, requests stop when the included credits run out. The profile
   cannot distinguish those balances or impose a promotional-credit-only cap.
3. The owner adds `claude_api_key` to `secrets/torrent.yaml` using sops. Never
   put the key in a Nix expression, Paseo's config, a prompt or a command argument.
   sops-nix installs the file for `agent`, so every agent can read it, and
   the API chat's tools inherit it from the environment. The limit on misuse
   is the credit cap, auto-reload off, no purchased balance and the key's
   expiry, not file permissions. No daemon restart is needed for key rotation:
   reload an API chat to launch a process with the replacement key.
4. Deploy the reviewed NixOS change on torrent after step 3. Until
   `claude_api_key` is in `secrets/torrent.yaml`, torrent's system does not
   build: sops-nix rejects the missing key. The managed config adds
   **Claude — API credits**. `paseo reload` applies profile changes without
   restarting ongoing sessions.

The owner's first test key expires after 30 days (created 2026-11-01). Replace
or renew it in the Console and sops before expiry if keeping this option.
Never move the test key out of `/run` into the project or a repository.

## When the subscription hits its limit

Paseo carries two patches for this (`modules/nixos/paseo/*.patch`, applied to
the daemon and the desktop app; the store mobile app shows none of the UI):

- `usage-limit-resume.patch` is upstream getpaseo/paseo#7193. Claude Code
  reports a refused turn with the exact reset time; the chat continues by
  itself a minute after it, unless its auto-resume switch is turned off.
- `limit-fallback.patch`: the profile above is marked `limitFallback`. A
  limited chat's callout offers **Continue on API credits**, which moves that
  same chat (same ID, conversation and folder) to the profile and continues
  it. Until the reset, new Claude chats start on the profile. At the reset,
  chats moved or started this way return to the subscription on their own.
  Chats deliberately started on **Claude — API credits** stay there.
- Spend: the profile's `creditBudget` makes the daemon record each turn's
  estimated cost in `~/.paseo/credit-ledger.jsonl` (as `agent`). The context
  meter of an API chat shows its spend and the cycle's total against $100.
  The Console's Billing page is authoritative. A chat moved from the
  subscription after a daemon restart may count its earlier subscription
  turns once, since the ledger only knows totals it has seen.

From the phone, or as an agent, the same move as the button:

```bash
paseo-continue-on-credits <Paseo-chat-ID-or-unique-prefix>
```

An exhausted or invalid key never switches back to subscription billing: the
API profile refuses to start without its key, and Anthropic answers an
exhausted balance with "Your credit balance is too low".

## Verification on 2026-11-01

A disposable subscription conversation hit the real weekly usage limit.
Its exact native session was imported under the API-key profile and correctly
recalled a marker from the earlier subscription-side prompt. Reported request
cost: $0.0122275. The owner confirmed promotional credit consumption,
auto-reload off and no purchased balance.

Returning to the original subscription view restored the API-side reply in its
history. Normal Claude still reported claude.ai authentication; the API wrapper
reported API-key authentication. A successful subscription response after reset
and permanent sops-backed deployment remain pending.

The patched daemon, on a separate Paseo home, against the same real limit:
the limit event recorded the reset (16:00 PT); **Continue on API credits**
moved the limited chat in place and it recalled a word from its
subscription-side turn; a new Claude chat started on the API profile.
The automatic return at the reset is checked separately.
