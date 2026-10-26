// paseo-resume: continue a Paseo agent whose turn stopped on a usage limit, once a
// fresh usage report for its account shows the quota back.
// usage: node resume-after-limit.mjs <paseo package> [--once] [--dry-run]
import { open, readdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const POLL_MS = 5 * 60_000;
// after a resume that hits the limit again: wait 30 min, then 60, 120, ...
const BACKOFF_MS = 30 * 60_000;
// enough of a transcript to reach its last turn
const TAIL_BYTES = 256 * 1024;
export const PROMPT = 'Your usage limit has reset. Continue where you left off.';

// codex's turn error: "You’ve hit your usage limit. Upgrade to Pro (…) or try again at 5:13 PM."
const CODEX_LIMIT = /^You['’]ve hit your [\w ]*limit\b/;

// claude code's own reply to a usage limit, never the model's, as the last entry of
// the main chain: "You've hit your session limit · resets 2:40pm (America/Los_Angeles)"
export function claudeLimit(jsonl) {
  const lines = jsonl.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try {
      e = JSON.parse(lines[i]);
    } catch {
      continue; // the cut first line, or a partial write
    }
    if ((e.type !== 'user' && e.type !== 'assistant') || e.isSidechain) continue;
    // background completions can be appended after a limit without starting a turn
    if (e.type === 'user' && e.origin?.kind === 'task-notification' && e.queueTranscriptOnly) continue;
    const synthetic = e.type === 'assistant' && e.isApiErrorMessage && e.error === 'rate_limit';
    return synthetic ? (e.message?.content?.[0]?.text ?? 'rate_limit') : null;
  }
  return null;
}

// the limit an agent stopped on, or null; reads only the daemon's list and claude's
// transcript, since fetching a timeline loads (starts) the agent
export async function limitHit(agent, readTranscript) {
  if (agent.archivedAt || agent.pendingPermissions?.length) return null;
  if (agent.status === 'error' && CODEX_LIMIT.test(agent.lastError ?? '')) return agent.lastError;
  // claude ends the turn as a normal reply (getpaseo/paseo#7636), or fails it once fixed
  const session = agent.persistence?.sessionId;
  if (agent.provider === 'claude' && (agent.status === 'idle' || agent.status === 'error') && session) {
    const jsonl = await readTranscript(agent.cwd, session);
    return jsonl ? claudeLimit(jsonl) : null;
  }
  return null;
}

// every summary window of the agent's account (5h, weekly) is under 100% again
export function quotaBack(reports) {
  const available = reports.filter((r) => r.report?.status === 'available');
  return (
    available.length > 0 &&
    available.every((r) => r.report.windows.filter((w) => w.summary).every((w) => w.usedPct < 100))
  );
}

// claude code keeps a session at ~/.claude/projects/<cwd, non-alphanumerics as ->/<id>.jsonl
async function readTranscript(cwd, session) {
  const projects = join(homedir(), '.claude', 'projects');
  const guess = cwd.replace(/[^a-zA-Z0-9]/g, '-');
  const dirs = [guess, ...(await readdir(projects).catch(() => [])).filter((d) => d !== guess)];
  for (const dir of dirs) {
    const f = await open(join(projects, dir, `${session}.jsonl`)).catch(() => null);
    if (!f) continue;
    try {
      const { size } = await f.stat();
      const length = Math.min(size, TAIL_BYTES);
      const { buffer } = await f.read(Buffer.alloc(length), 0, length, size - length);
      return buffer.toString('utf8');
    } finally {
      await f.close();
    }
  }
  return null;
}

// agentId -> { tries, notBefore }: resumes that ran into the limit again
const backoff = new Map();

// one pass over the daemon's agents
export async function poll(client, { dryRun = false, read = readTranscript } = {}) {
  const { entries } = await client.fetchAgents({});
  const seen = new Set();
  for (const { agent } of entries) {
    try {
      const hit = await limitHit(agent, read);
      if (!hit) continue;
      seen.add(agent.id);
      const b = backoff.get(agent.id);
      if (b && Date.now() < b.notBefore) continue;
      const { reports } = await client.listUsageReports({ agentId: agent.id, forceRefresh: true });
      if (!quotaBack(reports)) {
        console.log(`${agent.id} waiting: ${hit.slice(0, 120)}`);
        continue;
      }
      // archived (or continued by hand) while the usage refreshed: leave it
      const { entries: now } = await client.fetchAgents({});
      const current = now.find((e) => e.agent.id === agent.id)?.agent;
      if (!current || !(await limitHit(current, read))) continue;
      console.log(`${agent.id} resuming${dryRun ? ' (dry run)' : ''}: ${hit.slice(0, 120)}`);
      if (dryRun) continue;
      await client.sendAgentMessage(agent.id, PROMPT);
      const tries = (b?.tries ?? 0) + 1;
      backoff.set(agent.id, { tries, notBefore: Date.now() + BACKOFF_MS * 2 ** (tries - 1) });
    } catch (err) {
      console.error(`${agent.id} skipped: ${err?.message ?? err}`);
    }
  }
  // an agent past its limit starts over
  for (const id of backoff.keys()) if (!seen.has(id)) backoff.delete(id);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [lib, ...flags] = process.argv.slice(2);
  const once = flags.includes('--once');
  const dryRun = flags.includes('--dry-run');
  const { connectToDaemon } = await import(`${lib}/packages/cli/dist/utils/client.js`);
  const { selectDaemonTarget } = await import(`${lib}/packages/cli/dist/utils/daemon-target.js`);
  // a failed poll (the daemon still starting) exits; systemd starts it again
  for (;;) {
    const client = await connectToDaemon({ target: selectDaemonTarget({}, process.env, true) });
    try {
      await poll(client, { dryRun });
    } finally {
      await client.close().catch(() => {});
    }
    if (once) break;
    await new Promise((r) => setTimeout(r, POLL_MS));
  }
  process.exit(0);
}
