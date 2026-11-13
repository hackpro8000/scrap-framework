"""Engine checks (a part of PipelineHub): `engine <sha>` from a session
becomes a one-unit task of its own kind, leased like any unit (so a lost
machine's check is taken back and dealt again) but only to a machine whose
hello says it has cargo, g1 first. The machine checks the commit out, runs
scripts/build-model.sh --engine, and its output streams to the session."""
import json
import time

from hub_config import say
from hub_update import SHA
from units import Task

MAX_LINES = 500  # lines one engine-output message may carry
MAX_LINE = 2000


class EngineTask(Task):
	completed = True  # never written to the tasks file: a restarted hub drops it, its machine is told to stop
	chooses = True  # dealt first, to a machine with cargo

	def __init__(self, identity, commit, results):
		super().__init__(identity, 1, results)
		self.ref = commit

	def message(self, slot, lease):
		return json.dumps({"type": "engine", "id": self.id, "shard": slot, "commit": self.ref, "lease": lease.number if lease else 0})

	def choose(self, idle):
		"""An idle machine with cargo, g1 first."""
		cargo = [machine for machine in idle if machine.hello.get("cargo") is True]
		return next((machine for machine in cargo if machine.name == "g1"), cargo[0] if cargo else None)

	def state(self):
		return {**super().state(), "uploads_open": 0, "previews_waiting": 0}


class EngineChecks:
	async def engine_request(self, socket, request):
		hub = self.hub
		commit = request.get("commit")
		if not isinstance(commit, str) or not SHA.fullmatch(commit):
			await socket.send(json.dumps({"type": "error", "text": "engine wants a full 40-character commit sha"}))
			return
		identity = hub.new_task_id("e")
		task = hub.tasks[identity] = EngineTask(identity, commit, hub.results)
		hub.watchers.add(socket)
		task.watchers.add(socket)
		cargo = [machine.name for machine in hub.connected() if machine.hello.get("cargo") is True]
		say(f"engine check {identity} of {commit[:12]}; machines with cargo: {' '.join(cargo) or 'none yet'}")
		await socket.send(json.dumps({"type": "engine-posted", "task": identity, "cargo": cargo}))
		await hub.deal()
		await hub.follow(socket, task)

	async def tell_task(self, task, event):
		message = json.dumps(event)
		for watcher in list(task.watchers):
			try:
				await watcher.send(message)
			except Exception:
				task.watchers.discard(watcher)

	async def engine_event(self, task, shard, event, name):
		if event.get("type") == "engine-output":
			lines = event.get("lines") if isinstance(event.get("lines"), list) else []
			lines = [line[:MAX_LINE] for line in lines[:MAX_LINES] if isinstance(line, str)]
			await self.tell_task(task, {"type": "engine-output", "task": task.id, "machine": name, "lines": lines})
			return
		ok = event.get("ok") is True
		tail = event.get("tail") if isinstance(event.get("tail"), list) else []
		task.done[shard] = "status=DONE\n" if ok else "status=FAILED\n"
		lease = task.leases.get(shard)
		say(f"engine check {task.id} on {name}: {'ok' if ok else 'FAILED'}")
		await self.tell_task(task, {"type": "engine-finished", "task": task.id, "machine": name, "ok": ok, "code": event.get("code"),
			"tail": [line[:MAX_LINE] for line in tail[-200:] if isinstance(line, str)],
			"seconds": round(time.time() - lease.dealt) if lease else None})
		await self.hub.unit_over(task, shard)
		self.hub.tasks.pop(task.id, None)
