// Exercise the packaged adapters offline, including restored default modes.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const base = pathToFileURL(`${process.argv[2]}/lib/paseo/packages/server/dist/server/server/agent/`);
const { ClaudeAgentClient } = await import(new URL('providers/claude/agent.js', base));
const { CodexAppServerAgentClient, CodexAppServerAgentSession } = await import(new URL('providers/codex-app-server-agent.js', base));
const logger = { child() { return this; }, trace() {}, debug() {}, info() {}, warn() {}, error() {} };
const cwd = '/tmp';
const claude = new ClaudeAgentClient({ logger });
assert.equal(await claude.resolveDefaultModeId({ config: { provider: 'claude', cwd } }), 'bypassPermissions');
for (const [modeId, expected] of [[undefined, 'bypassPermissions'], ['default', 'bypassPermissions'], ['auto', 'bypassPermissions'], ['plan', 'plan'], ['acceptEdits', 'acceptEdits']]) {
  for (const resume of [false, true]) {
    const config = { provider: 'claude', cwd, modeId };
    const session = resume
      ? await claude.resumeSession({ sessionId: 'offline-test', metadata: config })
      : await claude.createSession(config);
    assert.equal(await session.getCurrentMode(), expected, `Claude ${modeId}, resume=${resume}`);
    await session.close();
  }
}
const codex = new CodexAppServerAgentClient(logger);
assert.equal(await codex.resolveDefaultModeId({ config: { provider: 'codex', cwd } }), 'full-access');
for (const [modeId, expected, approval, sandbox, nativeSandbox] of [[undefined, 'full-access', 'never', 'danger-full-access', 'dangerFullAccess'], ['auto', 'full-access', 'never', 'danger-full-access', 'dangerFullAccess'], ['auto-review', 'full-access', 'never', 'danger-full-access', 'dangerFullAccess'], ['read-only', 'read-only', 'on-request', 'read-only', 'readOnly']]) {
  for (const resume of [false, true]) {
    const session = new CodexAppServerAgentSession(
      { provider: 'codex', cwd, modeId }, resume ? { sessionId: 'offline-test' } : null,
      logger, async () => { throw Error('Offline test must not spawn a model'); },
    );
    assert.equal(await session.getCurrentMode(), expected);
    const start = session.buildThreadStartRequest('offline-model').params;
    assert.equal(start.approvalPolicy, approval);
    assert.equal(start.sandbox, sandbox);
    const turn = (await session.buildTurnStartParams('offline')).params;
    assert.equal(turn.approvalPolicy, approval);
    assert.equal(turn.sandboxPolicy.type, nativeSandbox);
    if (resume) {
      let resumed = false;
      session.client = { async request(method, params) {
        if (method === 'thread/loaded/list') return { data: [] };
        assert.equal(method, 'thread/resume');
        assert.equal(params.approvalPolicy, approval);
        assert.equal(params.sandbox, sandbox);
        resumed = true;
        return {};
      } };
      await session.ensureThreadLoaded();
      assert.ok(resumed);
      session.client = null;
    }
    await session.close();
  }
}
console.log('New and restored default modes bypass permissions; explicit Plan and Read-only modes remain intact.');
