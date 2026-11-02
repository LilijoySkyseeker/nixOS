// paseo-resume: continue a Codex agent whose turn stopped on a usage limit, once a
// fresh usage report for its account shows the quota back. Claude chats resume in
// the daemon itself (usage-limit-resume.patch), from the exact reset Claude reports.
// usage: node resume-after-limit.mjs <paseo package>
import { pathToFileURL } from 'node:url';

const POLL_MS = 5 * 60_000;
export const PROMPT = 'Your usage limit has reset. Continue where you left off.';

// codex's turn error: "You’ve hit your usage limit. Upgrade to Pro (…) or try again at 5:13 PM."
const CODEX_LIMIT = /^You['’]ve hit your [\w ]*limit\b/;

// the limit a codex agent stopped on, or null
export function limitHit(agent) {
  return agent.provider === 'codex' && agent.status === 'error' && CODEX_LIMIT.test(agent.lastError ?? '')
    ? agent.lastError
    : null;
}

// every summary window of the agent's account (5h, weekly) is under 100% again
export function quotaBack(reports) {
  const available = reports.filter((r) => r.report?.status === 'available');
  return (
    available.length > 0 &&
    available.every((r) => r.report.windows.filter((w) => w.summary).every((w) => w.usedPct < 100))
  );
}

// one pass over the daemon's agents
export async function poll(client) {
  const { entries } = await client.fetchAgents({});
  for (const { agent } of entries) {
    try {
      const hit = limitHit(agent);
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
