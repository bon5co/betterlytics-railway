// supervisord event listener: a program that has exhausted its restart retries
// is a permanently broken container, but supervisord keeps the remaining
// programs running and Railway keeps reporting the deploy healthy (the
// healthcheck only proves the Rust backend answers). Shut supervisord down and
// leave a marker so the entrypoint can exit non-zero and fail the deploy.
const fs = require('fs');

function send(line) { fs.writeSync(1, line); }

let buffer = '';
send('READY\n');

process.stdin.on('data', (chunk) => {
  buffer += chunk.toString();
  const newline = buffer.indexOf('\n');
  if (newline === -1) return;
  const header = buffer.slice(0, newline);
  const length = Number((header.match(/len:(\d+)/) || [])[1] || 0);
  if (buffer.length < newline + 1 + length) return;
  const payload = buffer.slice(newline + 1, newline + 1 + length);
  buffer = buffer.slice(newline + 1 + length);

  const name = (payload.match(/processname:([^\s]+)/) || [])[1] || 'unknown';
  send('RESULT 2\nOK');
  console.error(`[betterlytics] ${name} entered FATAL; stopping the container so the deploy fails loudly`);

  try {
    fs.writeFileSync('/run/betterlytics-fatal', name);
  } catch (err) {
    console.error(`[betterlytics] could not write the fatal marker: ${err.message}`);
  }

  // Signal supervisord itself, not PID 1: the entrypoint is a bash script that
  // runs supervisord as a foreground child, and bash defers a signal until that
  // child returns, so signalling PID 1 does nothing at all.
  try {
    const pid = Number(fs.readFileSync('/var/run/supervisord.pid', 'utf8').trim());
    process.kill(pid, 'SIGTERM');
  } catch (err) {
    console.error(`[betterlytics] could not stop supervisord: ${err.message}`);
    process.kill(1, 'SIGKILL');
  }
});
