import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listAgents, resolveSource } from '../modules/nixos/paseo/continue-on-credits.mjs';

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
