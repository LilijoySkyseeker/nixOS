// The watcher on recorded provider messages and a fake daemon, offline.
import assert from 'node:assert/strict';
const { limitHit, quotaBack, poll, PROMPT } = await import(process.argv[2]);
const limitText = "You've hit your session limit · resets 2:40pm (America/Los_Angeles)";
const codex = 'You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/settings/usage to purchase more credits or try again at 5:13 PM.';
const line = (o) => JSON.stringify(o);
const user = line({ type: 'user', isSidechain: false, message: { role: 'user', content: 'go on' } });
const reply = (text) => line({ type: 'assistant', isSidechain: false, message: { model: 'claude-opus-5-5', content: [{ type: 'text', text }] } });
// as claude code writes it, then its notice
const limit = line({ type: 'assistant', isSidechain: false, error: 'rate_limit', isApiErrorMessage: true, message: { model: '<synthetic>', content: [{ type: 'text', text: limitText }] } });
const notice = line({ type: 'system', subtype: 'informational', content: 'Usage limit reached · continuing automatically at 2:40pm' });
const taskNotice = line({ type: 'user', isSidechain: false, origin: { kind: 'task-notification', producer: 'session-task' }, queueTranscriptOnly: true, message: { role: 'user', content: '<task-notification>Agent failed: usage limit</task-notification>' } });
const side = (s) => s.replace('"isSidechain":false', '"isSidechain":true');
const claude = (status, ...lines) => [{ provider: 'claude', status, cwd: '/home/agent/work', persistence: { sessionId: 's' } }, async () => `{"cut":\n${lines.join('\n')}\n`];
const hit = (agent, read = async () => null) => limitHit(agent, read);

assert.equal(await hit({ provider: 'codex', status: 'error', lastError: codex }), codex);
assert.equal(await hit(...claude('idle', user, limit)), limitText);
assert.equal(await hit(...claude('idle', user, limit, notice)), limitText);
assert.equal(await hit(...claude('idle', user, limit, taskNotice, taskNotice)), limitText);
// once paseo fails the turn (getpaseo/paseo#7636)
assert.equal(await hit(...claude('error', user, limit)), limitText);
// already continued, a subagent's limit, or the model only saying it
assert.equal(await hit(...claude('idle', limit, user)), null);
assert.equal(await hit(...claude('idle', limit, taskNotice, user)), null);
assert.equal(await hit(...claude('idle', user, reply('Done'), taskNotice)), null);
// a notification delivered as a new turn still supersedes the old limit
assert.equal(await hit(...claude('idle', limit, taskNotice.replace('"queueTranscriptOnly":true', '"queueTranscriptOnly":false'))), null);
assert.equal(await hit(...claude('idle', user, side(limit))), null);
assert.equal(await hit(...claude('idle', user, reply(limitText))), null);
// a turn still going, archived, waiting on a permission, no transcript, another error
assert.equal(await hit(...claude('running', user, limit)), null);
assert.equal(await hit({ ...claude('idle')[0], archivedAt: '2026-10-26T00:00:44Z' }, claude('idle', limit)[1]), null);
assert.equal(await hit({ ...claude('idle')[0], pendingPermissions: [{}] }, claude('idle', limit)[1]), null);
assert.equal(await hit(claude('idle')[0]), null);
assert.equal(await hit({ provider: 'codex', status: 'error', lastError: 'Overloaded' }), null);
assert.equal(await hit({ provider: 'codex', status: 'idle', lastError: codex }), null);

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
const daemon = ({ agents, usedPct = 41, onUsage = () => {} }) => {
  const sent = [];
  return {
    sent,
    fetchAgents: async () => ({ entries: agents().map((agent) => ({ agent })) }),
    listUsageReports: async () => (onUsage(), { reports: [report(w(usedPct), w(5))] }),
    sendAgentMessage: async (id, text) => sent.push([id, text]),
  };
};
const read = claude('idle', user, limit)[1];
const limited = (id, extra = {}) => ({ id, provider: 'claude', status: 'idle', cwd: '/home/agent/work', persistence: { sessionId: id }, ...extra });
// quota back: sent once, then held by the backoff
let d = daemon({ agents: () => [limited('a')] });
await poll(d, { read });
assert.deepEqual(d.sent, [['a', PROMPT]]);
await poll(d, { read });
assert.equal(d.sent.length, 1);
// quota still out: nothing sent
d = daemon({ agents: () => [limited('b')], usedPct: 100 });
await poll(d, { read });
assert.equal(d.sent.length, 0);
// archived while its usage refreshed: the daemon's list drops it, and it isn't sent
let archived = false;
d = daemon({ agents: () => (archived ? [] : [limited('d')]), onUsage: () => (archived = true) });
await poll(d, { read });
assert.equal(d.sent.length, 0);
// one agent that fails to check doesn't stop the others
d = daemon({ agents: () => [limited('bad'), limited('e')] });
await poll(d, { read: async (cwd, id) => { if (id === 'bad') throw Error('gone'); return read(); } });
assert.deepEqual(d.sent, [['e', PROMPT]]);
console.log('paseo-resume decisions ok');
