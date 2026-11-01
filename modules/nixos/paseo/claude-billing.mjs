// One manual handover, using the same disk-backed Claude conversation.
import { pathToFileURL } from 'node:url';

const claudeProviders = ['claude', 'claude-api-credits'];

// Every agent, archived included: a missed child would be cascade-archived.
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

export async function switchBilling(client, source, provider, agents) {
  if (!claudeProviders.includes(source.provider)) {
    throw new Error('Only Claude subscription/API-credit sessions can switch billing.');
  }
  if (source.archivedAt || ['running', 'initializing'].includes(source.status) ||
      source.pendingPermissions?.length) {
    throw new Error('The source chat must be unarchived and stopped before switching.');
  }
  const sessionId = source.persistence?.sessionId;
  if (!sessionId || !source.cwd) throw new Error('No saved Claude conversation to resume.');
  if (source.provider === provider) throw new Error(`Chat already uses ${provider}.`);
  // Paseo cascades archive to child agents. Do not interrupt their work.
  if (agents.some((a) => !a.archivedAt && a.labels?.['parent-agent-id'] === source.id)) {
    throw new Error('Archive completed child agents or detach unfinished ones before switching.');
  }
  if (agents.some((a) => a.id !== source.id && !a.archivedAt &&
      claudeProviders.includes(a.provider) && a.persistence?.sessionId === sessionId)) {
    throw new Error('Another chat already has this Claude conversation open.');
  }
  // The list may be stale: a message sent since then would be cut off.
  const current = (await client.fetchAgent(source.id))?.agent;
  if (!current || current.archivedAt || ['running', 'initializing'].includes(current.status) ||
      current.pendingPermissions?.length) {
    throw new Error('The source chat started working or changed; try again when it is stopped.');
  }
  const request = {
    provider, sessionId, cwd: source.cwd,
    ...(source.workspaceId ? { workspaceId: source.workspaceId } : {}),
    ...(source.labels ? { labels: source.labels } : {}),
  };
  await client.archiveAgent(source.id);
  let target;
  try {
    target = await client.importAgent(request);
    // Returning to an old Paseo view must reload messages written by the other profile.
    await client.refreshAgent(target.id);
    const model = source.runtimeInfo?.model ?? source.model;
    if (model && model !== 'default') await client.setAgentModel(target.id, model);
    if (source.effectiveThinkingOptionId) {
      await client.setAgentThinkingOption(target.id, source.effectiveThinkingOptionId);
    }
    if (source.currentModeId) await client.setAgentMode(target.id, source.currentModeId);
    if (source.title) await client.updateAgent(target.id, { name: source.title });
    return { agentId: target.id, provider, sessionId, cwd: source.cwd };
  } catch (error) {
    // A failed import/configuration must leave the original conversation usable.
    const failures = [error.message];
    const recover = `paseo import --provider ${source.provider} --cwd ${source.cwd} ${sessionId}`;
    try {
      if (target) await client.archiveAgent(target.id);
    } catch (archiveError) {
      // Restoring now would open a second writer on the same transcript.
      failures.push(`closing ${target.id} failed: ${archiveError.message}`,
        `chat ${target.id} still holds the conversation under ${provider}; use it, or archive it and run: ${recover}`);
      throw new Error(failures.join('; '), { cause: error });
    }
    try {
      const restored = await client.importAgent({ ...request, provider: source.provider });
      await client.refreshAgent(restored.id);
    } catch (rollbackError) {
      failures.push(`restoring chat ${source.id} also failed: ${rollbackError.message}`,
        `the transcript is intact; recover with: ${recover}`);
    }
    throw new Error(failures.join('; '), { cause: error });
  }
}

async function main() {
  const [lib, id, choice] = process.argv.slice(2);
  if (!lib || !id || !['api', 'subscription'].includes(choice)) {
    throw new Error('Usage: paseo-claude-billing <Paseo chat ID or unique prefix> <api|subscription>');
  }
  const { connectToDaemon } = await import(`${lib}/packages/cli/dist/utils/client.js`);
  const { selectDaemonTarget } = await import(`${lib}/packages/cli/dist/utils/daemon-target.js`);
  const client = await connectToDaemon({ target: selectDaemonTarget({}, process.env, true) });
  try {
    const agents = await listAgents(client);
    const source = resolveSource(id, agents);
    console.log(`Switching "${source.title ?? source.id}" (${source.id}) in ${source.cwd}`);
    const result = await switchBilling(client, source,
      choice === 'api' ? 'claude-api-credits' : 'claude', agents);
    console.log(JSON.stringify(result, null, 2));
    console.log('Open this chat in Paseo and send continue when ready.');
  } finally {
    await client.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
