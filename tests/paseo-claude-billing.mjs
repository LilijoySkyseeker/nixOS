import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listAgents, resolveSource, switchBilling } from '../modules/nixos/paseo/claude-billing.mjs';

const source = {
  id: 'original', provider: 'claude', status: 'idle', cwd: '/work/project',
  persistence: { sessionId: 'native-conversation' }, workspaceId: 'workspace',
  model: 'claude-sonnet-5-5', effectiveThinkingOptionId: 'high',
  currentModeId: 'plan', title: 'Ongoing work', labels: { project: 'work' },
};
function client() {
  const calls = [];
  const api = { calls };
  for (const method of ['archiveAgent', 'refreshAgent', 'setAgentModel',
    'setAgentThinkingOption', 'setAgentMode', 'updateAgent']) {
    api[method] = async (...args) => calls.push([method, ...args]);
  }
  api.fetchAgent = async (id) => ({ agent: { ...source, id } });
  api.importAgent = async (request) => {
    calls.push(['importAgent', request]);
    return { id: request.provider === 'claude' ? 'original' : 'api-view' };
  };
  return api;
}

test('handover closes the old writer and preserves native conversation, cwd and settings', async () => {
  const api = client();
  const result = await switchBilling(api, source, 'claude-api-credits', [source]);
  assert.deepEqual(api.calls[0], ['archiveAgent', 'original']);
  assert.deepEqual(api.calls[1], ['importAgent', {
    provider: 'claude-api-credits', sessionId: 'native-conversation',
    cwd: '/work/project', workspaceId: 'workspace', labels: { project: 'work' },
  }]);
  assert.deepEqual(api.calls.slice(2), [
    ['refreshAgent', 'api-view'], ['setAgentModel', 'api-view', 'claude-sonnet-5-5'],
    ['setAgentThinkingOption', 'api-view', 'high'], ['setAgentMode', 'api-view', 'plan'],
    ['updateAgent', 'api-view', { name: 'Ongoing work' }],
  ]);
  assert.equal(result.sessionId, 'native-conversation');
});

test('running, archived, unsaved and wrong-provider chats are rejected before mutation', async () => {
  for (const override of [{ status: 'running' }, { archivedAt: 'today' },
    { persistence: null }, { provider: 'codex' }, { pendingPermissions: [{}] }]) {
    const api = client();
    await assert.rejects(switchBilling(api, { ...source, ...override }, 'claude-api-credits', []));
    assert.equal(api.calls.length, 0);
  }
});

test('a chat that started working since the list was read is not archived', async () => {
  const api = client();
  api.fetchAgent = async () => ({ agent: { ...source, status: 'running' } });
  await assert.rejects(switchBilling(api, source, 'claude-api-credits', [source]), /started working/);
  assert.equal(api.calls.length, 0);
});

test('handover refuses to cascade archive children or create a second transcript writer', async () => {
  for (const other of [
    { id: 'child', labels: { 'parent-agent-id': 'original' } },
    { id: 'other-view', provider: 'claude-api-credits', persistence: source.persistence },
  ]) {
    const api = client();
    await assert.rejects(switchBilling(api, source, 'claude-api-credits', [source, other]));
    assert.equal(api.calls.length, 0);
  }
});

test('failed target configuration closes it and restores the source instead of leaving two writers', async () => {
  const api = client();
  api.setAgentModel = async () => { throw new Error('model unavailable'); };
  await assert.rejects(switchBilling(api, source, 'claude-api-credits', [source]), /model unavailable/);
  assert.deepEqual(api.calls.slice(-3), [
    ['archiveAgent', 'api-view'],
    ['importAgent', { provider: 'claude', sessionId: 'native-conversation',
      cwd: '/work/project', workspaceId: 'workspace', labels: { project: 'work' } }],
    ['refreshAgent', 'original'],
  ]);
});

test('a target that cannot be closed is left as the only writer, with the recovery named', async () => {
  const api = client();
  api.setAgentModel = async () => { throw new Error('model unavailable'); };
  const archive = api.archiveAgent;
  api.archiveAgent = async (id) => {
    if (id === 'api-view') throw new Error('daemon gone');
    return archive(id);
  };
  await assert.rejects(switchBilling(api, source, 'claude-api-credits', [source]),
    /model unavailable; closing api-view failed: daemon gone; .*paseo import --provider claude --cwd \/work\/project native-conversation/);
  assert.ok(!api.calls.some(([method, request]) => method === 'importAgent' && request.provider === 'claude'));
});

test('a failed restore names the recovery command', async () => {
  const api = client();
  api.setAgentModel = async () => { throw new Error('model unavailable'); };
  const importAgent = api.importAgent;
  api.importAgent = async (request) => {
    if (request.provider === 'claude') throw new Error('daemon gone');
    return importAgent(request);
  };
  await assert.rejects(switchBilling(api, source, 'claude-api-credits', [source]),
    /restoring chat original also failed: daemon gone; the transcript is intact; recover with: paseo import --provider claude/);
});

test('every page of agents is read, archived and background included', async () => {
  const requests = [];
  const pages = { undefined: ['a', 'next'], next: ['b', null] };
  const api = {
    supportsBackgroundWorkspaces: () => true,
    fetchAgents: async (options) => {
      requests.push(options);
      const [id, nextCursor] = pages[options.page.cursor];
      return { entries: [{ agent: { id } }], pageInfo: { nextCursor } };
    },
  };
  assert.deepEqual((await listAgents(api)).map((a) => a.id), ['a', 'b']);
  assert.equal(requests[1].page.cursor, 'next');
  assert.deepEqual(requests[0].filter, { includeArchived: true, includeBackground: true });
});

test('only an exact ID or a unique ID prefix selects a chat', () => {
  const agents = [{ id: 'abc1', title: 'x' }, { id: 'abc2', title: 'abc3' }];
  assert.equal(resolveSource('abc2', agents).id, 'abc2');
  assert.equal(resolveSource('abc1', agents).id, 'abc1');
  assert.throws(() => resolveSource('abc', agents), /Ambiguous/);
  assert.throws(() => resolveSource('abc3', agents), /not found/);
});
