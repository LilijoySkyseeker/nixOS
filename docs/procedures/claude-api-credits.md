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

## Continue an existing conversation

Run as `agent`, or ask an agent to do this for the selected chat:

```bash
paseo-claude-billing <Paseo-chat-ID-or-unique-prefix> api
```

The command archives the original Paseo view, imports the **same Claude session
ID and working directory** under the API profile, reloads its history, and
preserves the model, thinking level, permission mode and title. It prints the
Paseo chat ID to open. Send `continue` there. No model request is sent by the
switch command itself.

After subscription usage resets:

```bash
paseo-claude-billing <API-chat-ID> subscription
```

This closes the API view and restores the subscription view with the messages
written during API use. The two views share one Claude transcript: never run
both at once. The helper refuses running chats, pending permission requests,
unarchived child agents, and another open view of the same transcript. Finish
or detach child work first. It re-checks the chat just before closing it. If
the handover fails, it restores the original view; if even that fails, it
prints the `paseo import` command that brings the conversation back. The
transcript on disk is never touched. A model the API key can't use fails the
handover and restores the original.

A new API-backed conversation can also be started by choosing **Claude — API
credits** in Paseo. Ordinary **Claude** keeps subscription authentication.
The API profile refuses to start if its key is missing or empty; an exhausted
or invalid key does not switch back to subscription billing.

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
