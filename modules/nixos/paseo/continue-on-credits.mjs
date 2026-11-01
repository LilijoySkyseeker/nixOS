// The limit callout's "Continue on API credits", for a client without the patched UI
// (the store mobile app) or an agent: moves a chat stopped at its limit in place.
import { pathToFileURL } from 'node:url';

// Every agent, archived included, so a prefix can't silently miss its match.
export async function listAgents(client) {
  const agents = [];
  let cursor;
  do {
    const page = await client.fetchAgents({
      filter: {
        includeArchived: true,
        ...(client.supportsBackgroundWorkspaces?.() ? { includeBackground: true } : {}),
      },
      sort: [{ key: 'created_at', direction: 'desc' }],
      page: { limit: 200, ...(cursor ? { cursor } : {}) },
    });
    agents.push(...page.entries.map((entry) => entry.agent));
    cursor = page.pageInfo?.nextCursor ?? undefined;
  } while (cursor);
  return agents;
}

// Exact ID or a prefix of exactly one ID; never a title or a guess.
export function resolveSource(id, agents) {
  const exact = agents.find((agent) => agent.id === id);
  if (exact) return exact;
  const matches = agents.filter((agent) => agent.id.startsWith(id));
  if (matches.length === 1) return matches[0];
  if (matches.length === 0) throw new Error(`Chat not found: ${id}`);
  throw new Error(`Ambiguous chat ID ${id}: ${matches.map((a) => a.id).join(', ')}`);
}

async function main() {
  const [lib, id] = process.argv.slice(2);
  if (!lib || !id) throw new Error('Usage: paseo-continue-on-credits <Paseo chat ID or unique prefix>');
  const { connectToDaemon } = await import(`${lib}/packages/cli/dist/utils/client.js`);
  const { selectDaemonTarget } = await import(`${lib}/packages/cli/dist/utils/daemon-target.js`);
  const client = await connectToDaemon({ target: selectDaemonTarget({}, process.env, true) });
  try {
    const source = resolveSource(id, await listAgents(client));
    console.log(`Continuing "${source.title ?? source.id}" (${source.id}) on API credits`);
    await client.continueOnLimitFallback(source.id);
  } finally {
    await client.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
