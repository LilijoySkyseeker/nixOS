// paseo-resume: continue a Paseo agent whose turn stopped on a usage limit, once a
// fresh usage report for its account shows the quota back.
// usage: node resume-after-limit.mjs <paseo package>
import { open } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const POLL_MS = 5 * 60_000;
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
    if (e.type !== 'user' && e.type !== 'assistant') continue;
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
  if (agent.status === 'error' && CODEX_LIMIT.test(agent.lastError ?? '')) return agent.lastError;
  // claude ends the turn as a normal reply (getpaseo/paseo#7636)
  const session = agent.persistence?.sessionId;
  if (agent.provider === 'claude' && agent.status === 'idle' && session) {
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
  const f = await open(join(projects, cwd.replace(/[^a-zA-Z0-9]/g, '-'), `${session}.jsonl`)).catch(() => null);
  if (!f) return null;
  try {
    const { size } = await f.stat();
    const length = Math.min(size, TAIL_BYTES);
    const { buffer } = await f.read(Buffer.alloc(length), 0, length, size - length);
    return buffer.toString('utf8');
  } finally {
    await f.close();
  }
}

// one pass over the daemon's agents
export async function poll(client, { read = readTranscript } = {}) {
  const { entries } = await client.fetchAgents({});
  for (const { agent } of entries) {
    try {
      const hit = await limitHit(agent, read);
      if (!hit) continue;
      const { reports } = await client.listUsageReports({ agentId: agent.id, forceRefresh: true });
      if (!quotaBack(reports)) {
        console.log(`${agent.id} waiting: ${hit.slice(0, 120)}`);
        continue;
      }
      console.log(`${agent.id} resuming: ${hit.slice(0, 120)}`);
      await client.sendAgentMessage(agent.id, PROMPT);
    } catch (err) {
      console.error(`${agent.id} skipped: ${err?.message ?? err}`);
    }
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [lib] = process.argv.slice(2);
  const { connectToDaemon } = await import(`${lib}/packages/cli/dist/utils/client.js`);
  const { selectDaemonTarget } = await import(`${lib}/packages/cli/dist/utils/daemon-target.js`);
  // paseo.service is up before its socket is: retry a failed connect here, so the
  // unit doesn't fail during a switch; any other error exits and systemd restarts it
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  for (;;) {
    let client;
    for (let tries = 1; !client; tries++) {
      try {
        client = await connectToDaemon({ target: selectDaemonTarget({}, process.env, true) });
      } catch (err) {
        if (err?.code !== 'DAEMON_NOT_RUNNING' || tries >= 12) throw err;
        await sleep(5_000);
      }
    }
    try {
      await poll(client);
    } finally {
      await client.close().catch(() => {});
    }
    await sleep(POLL_MS);
  }
}
