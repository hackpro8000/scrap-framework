"""PipelineAgent mixin: an engine check. {"type": "engine", "id", "shard",
"commit", "lease"} is a unit like a build's (taken and cancelled by the
agent the same way): the commit is checked out and scripts/build-model.sh
--engine compiles it (and shares the binary on the build-engine branch). Its
output goes to the hub as it comes, {"type": "engine-output", "lines"}, and
{"type": "engine-done", "ok", "code", "tail"} (the last 200 lines) ends it.
The cargo target folder stays in the checkout, so the next check compiles
only what changed."""
import asyncio
import collections
import json
import os
import shutil
import subprocess
import time

from agent.common import SCRIPTS
from agent.update import SHA

TAIL_LINES = 200
BATCH_LINES = 50
BATCH_SECONDS = 0.5


class EngineUnits:
	@staticmethod
	def engine_fits(event):
		"""Whether an engine message names a unit and a full commit."""
		commit = event.get("commit")
		return (isinstance(event.get("id"), str) and isinstance(event.get("shard"), int)
			and isinstance(commit, str) and SHA.fullmatch(commit) is not None)

	async def run_engine(self, unit, event, work):
		commit = event["commit"]
		out = os.path.join("results", f"{unit[0]}-S{unit[1]}")
		shutil.rmtree(out, ignore_errors=True)
		os.makedirs(out, exist_ok=True)
		log = os.path.join(out, "engine.log")
		self.agent.begin(unit, "engine", log)
		try:
			code, tail = await asyncio.to_thread(self.compile_engine, unit, commit, work, log, asyncio.get_running_loop())
		except Exception as error:
			code, tail = 1, [f"engine check could not run: {error}"]
		if not work["cancelled"]:
			await self.agent.send(json.dumps({"type": "engine-done", "task": unit[0], "shard": unit[1], "lease": work.get("lease"),
				"ok": code == 0, "code": code, "tail": tail[-TAIL_LINES:]}))
		return False

	def compile_engine(self, unit, commit, work, log_path, loop):
		"""Runs in a thread: checkout, then the compile, its lines sent in
		batches as they come. Returns (exit code, last lines)."""
		agent = self.agent

		def send(lines):
			message = json.dumps({"type": "engine-output", "task": unit[0], "shard": unit[1], "lease": work.get("lease"), "lines": lines})
			asyncio.run_coroutine_threadsafe(agent.send(message), loop)

		with open(log_path, "w") as log:
			work["checkout"] = True
			ok = agent.run_process(work, ["git", "fetch", "-q", "--depth=1", "origin", commit], stdout=log, stderr=log)[0] == 0
			ok = ok and agent.run_process(work, ["git", "checkout", "-q", "-f", commit], stdout=log, stderr=log)[0] == 0
			work["checkout"] = False
		if not ok:
			with open(log_path, errors="replace") as log:
				lines = [f"engine check: could not check out {commit[:12]}", *log.read().splitlines()]
			send(lines[-TAIL_LINES:])
			return 1, lines
		if work["cancelled"]:
			return -9, []
		environment = {**os.environ, "MODELKIT_SHARE_ENGINE": "1", "CARGO_TERM_COLOR": "never"}
		# Not as a shard: a shard other than 1 would wait for machine 1's engine.
		environment.pop("SHARD", None)
		environment.pop("MODELKIT_NO_COMPILE", None)
		process = subprocess.Popen([os.path.join(SCRIPTS, "build-model.sh"), "--engine"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
			text=True, errors="replace", env=environment, start_new_session=True)
		work["processes"].add(process)
		tail, batch, sent = collections.deque(maxlen=TAIL_LINES), [], time.monotonic()
		try:
			with open(log_path, "a") as log:
				for line in process.stdout:
					line = line.rstrip("\n")
					log.write(line + "\n")
					log.flush()
					tail.append(line)
					batch.append(line)
					if len(batch) >= BATCH_LINES or time.monotonic() - sent >= BATCH_SECONDS:
						send(batch)
						batch, sent = [], time.monotonic()
			if batch:
				send(batch)
			process.wait()
		finally:
			work["processes"].discard(process)
		return process.returncode, list(tail)
