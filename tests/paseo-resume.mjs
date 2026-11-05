// The watcher on recorded provider messages and a fake daemon, offline.
import assert from 'node:assert/strict';
const { limitHit, quotaBack, poll, PROMPT } = await import(process.argv[2]);
const codex = 'You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/settings/usage to purchase more credits or try again at 5:13 PM.';
const limited = (id) => ({ id, provider: 'codex', status: 'error', lastError: codex });

assert.equal(limitHit(limited('a')), codex);
assert.equal(limitHit({ provider: 'codex', status: 'error', lastError: 'Overloaded' }), null);
assert.equal(limitHit({ provider: 'codex', status: 'idle', lastError: codex }), null);
// claude limits are the daemon's (usage-limit-resume.patch)
assert.equal(limitHit({ provider: 'claude', status: 'error', lastError: codex }), null);

const report = (...windows) => ({ fetchedAt: '2026-10-26T02:38:03Z', report: { status: 'available', windows } });
const w = (usedPct, summary = true) => ({ id: 'w', summary, usedPct });
assert.equal(quotaBack([report(w(41), w(5))]), true);
assert.equal(quotaBack([report(w(100), w(5))]), false);
assert.equal(quotaBack([report(w(41), w(100))]), false);
// a per-model window (weekly · Fable) isn't the account's
assert.equal(quotaBack([report(w(41), w(100, null))]), true);
assert.equal(quotaBack([{ report: { status: 'unavailable' } }]), false);
assert.equal(quotaBack([]), false);

// whole polls against a fake daemon: what gets sent
const daemon = ({ agents, usedPct = 41, failFor }) => {
  const sent = [];
  return {
    sent,
    fetchAgents: async () => ({ entries: agents().map((agent) => ({ agent })) }),
    listUsageReports: async ({ agentId }) => {
      if (agentId === failFor) throw Error('gone');
      return { reports: [report(w(usedPct), w(5))] };
    },
    sendAgentMessage: async (id, text) => sent.push([id, text]),
  };
};
// quota back: sent
let d = daemon({ agents: () => [limited('a')] });
await poll(d);
assert.deepEqual(d.sent, [['a', PROMPT]]);
// quota still out: nothing sent
d = daemon({ agents: () => [limited('b')], usedPct: 100 });
await poll(d);
assert.equal(d.sent.length, 0);
// one agent that fails to check doesn't stop the others
d = daemon({ agents: () => [limited('bad'), limited('e')], failFor: 'bad' });
await poll(d);
assert.deepEqual(d.sent, [['e', PROMPT]]);
console.log('paseo-resume decisions ok');
