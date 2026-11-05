// TODO: drop when the paseo cli can set a schedule's archive-on-finish
// keep-runs: turn off archive-on-finish for the given schedules, which the
// paseo cli can't set; their runs archive themselves
// usage: node keep-runs.mjs <paseo package> <schedule id>...
const [lib, ...ids] = process.argv.slice(2);
const { connectToDaemon } = await import(`${lib}/packages/cli/dist/utils/client.js`);
const { selectDaemonTarget } = await import(`${lib}/packages/cli/dist/utils/daemon-target.js`);
const client = await connectToDaemon({ target: selectDaemonTarget({}, process.env, true) });
try {
  for (const id of ids) {
    const r = await client.scheduleUpdate({ id, newAgentConfig: { archiveOnFinish: false } });
    if (r.error) throw new Error(`${id}: ${r.error}`);
  }
} finally {
  await client.close().catch(() => {});
}
