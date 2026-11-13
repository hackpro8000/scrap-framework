"""The control port: admitting a session by its signed nonce and answering
its requests (a part of Coordinator), and the checks serve makes on control.
Requests of kinds the hub does not answer itself go to the plugin that
registered the kind (HubPlugins.request)."""
import asyncio
import ipaddress
import json
import os
import subprocess
import sys
import tempfile
import time

import websockets

from hub_config import CHALLENGE_SECONDS, CONTROL_NAMESPACE, MAX_SIGNATURE, MAX_WORKERS, TAILNET, say


class SessionControl:
	# --- the session ---

	async def admit(self, socket):
		"""Challenges a control connection; returns its request once the
		answer verifies, else None. The answer and the request may come in
		either order, and nothing is acted on before both are in."""
		nonce = os.urandom(32).hex()
		await socket.send(json.dumps({"type": "challenge", "nonce": nonce}))
		try:
			messages = await asyncio.wait_for(self.two_messages(socket), CHALLENGE_SECONDS)
		except (asyncio.TimeoutError, ValueError):
			return None
		answers = [message for message in messages if isinstance(message, dict) and message.get("type") == "answer"]
		requests = [message for message in messages if isinstance(message, dict) and message.get("type") != "answer"]
		if len(answers) != 1 or len(requests) != 1 or not await self.signed(nonce, answers[0].get("signature")):
			say("control connection refused: no valid signature")
			return None
		return requests[0]

	async def two_messages(self, socket):
		return [json.loads(await socket.recv()) for _ in range(2)]

	async def signed(self, nonce, signature):
		if not isinstance(signature, str) or len(signature) >= MAX_SIGNATURE or not signature.isascii():
			return False
		with tempfile.NamedTemporaryFile("w", suffix=".sig") as file:
			file.write(signature)
			file.flush()
			check = await asyncio.create_subprocess_exec("ssh-keygen", "-Y", "verify", "-f", self.control_signers,
				"-I", CONTROL_NAMESPACE, "-n", CONTROL_NAMESPACE, "-s", file.name,
				stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
			await check.communicate(nonce.encode())
		return check.returncode == 0

	async def control(self, socket, path=None):
		try:
			request = await self.admit(socket) if self.control_signers else json.loads(await socket.recv())
		except websockets.ConnectionClosed:
			return
		if request is None:
			await socket.close()
			return
		kind = request.get("type")
		if kind == "update":
			await self.update_request(socket, request)
			return
		if kind == "status":
			now = time.time()
			connected = self.connected()
			await socket.send(json.dumps({"type": "status", "run": self.run_id, "count": self.count,
				"up": [machine.name for machine in connected], "tasks": list(self.tasks),
				"github_up": self.machines_event()["github_up"],
				"roster": [machine.state(now) for machine in self.roster.values()],
				"progress": {machine.name: machine.progress for machine in self.roster.values() if machine.progress and machine.lease},
				"queues": {task.id: len(task.queue) for task in self.tasks.values()},
				"machines": sorted(int(machine.name[1:]) for machine in connected if machine.kind == "numbered"),
				"lease_seconds": {"grace": self.grace, "silent": self.silent, "wedged": self.wedged},
				"task_states": self.task_states(), "run_started": self.run_started, "notes": "".join(self.plugins.notes).strip(),
				**self.code_state(), **self.lifetime()}))
			return
		if kind == "clear-tasks":
			# Tasks no machine is working on (ALERT STRANDED_TASK); a machine
			# still on one of their units is told to stop.
			cleared = list(self.tasks)
			for task in self.tasks.values():
				for slot, lease in task.leases.items():
					machine = self.roster.get(lease.machine)
					if machine and machine.lease == (task.id, slot):
						machine.lease = None
						await self.tell_cancel(machine, task.id, slot)
			self.tasks.clear()
			self.save_tasks()
			say(f"cleared {len(cleared)} tasks: {' '.join(cleared)}")
			await socket.send(json.dumps({"type": "cleared", "tasks": cleared}))
			return
		if kind == "watch":
			# Streams machine and task events until the watcher hangs up.
			await socket.send(json.dumps({"type": "machines", "run": self.run_id, "count": self.count, "up": len(self.connected())}))
			self.watchers.add(socket)
			try:
				async for _ in socket:
					pass
			except websockets.ConnectionClosed:
				pass
			finally:
				self.watchers.discard(socket)
			return
		if kind == "watch-task":
			await self.watch_task(socket, request.get("task"))
			return
		if kind == "mint-workers":
			# Tokens admit machines, so only a signed session may ask for them.
			if not self.control_signers and not self.test_without_identity:
				await socket.send(json.dumps({"type": "error", "text": "mint-workers needs a coordinator started with --control-key"}))
				return
			count = request.get("count")
			if not isinstance(count, int) or not 1 <= count <= MAX_WORKERS:
				await socket.send(json.dumps({"type": "error", "text": f"mint-workers wants a count from 1 to {MAX_WORKERS}"}))
				return
			pool, minted = self.mint(count)
			await socket.send(json.dumps({"type": "workers", "pool": pool, "workers": minted}))
			return
		if kind == "stop-machines":
			connected = self.connected()
			for machine in connected:
				await self.send_to(machine, json.dumps({"type": "stop"}))
			await socket.send(json.dumps({"type": "stopped", "machines": len(connected)}))
			return
		handler = self.plugins.requests.get(kind) if isinstance(kind, str) else None
		if handler is None:
			await socket.send(json.dumps({"type": "error", "text": f"unknown request {kind}"}))
			return
		await handler(socket, request)

	async def watch_task(self, socket, identity):
		"""A session whose connection dropped mid-task picks it up again: the
		files relayed while it was gone, what the task's kind replays
		(Task.replay), every unit that is over, and the finished event if the
		task has finished, so it neither waits for nor reports as stalled
		what already ended."""
		task, ended = self.tasks.get(identity), self.finished.get(identity)
		if not task and not ended:
			await socket.send(json.dumps({"type": "error", "text": f"the coordinator does not know task {identity}"}))
			return
		task = task or ended[0]
		self.watchers.add(socket)
		task.watchers.add(socket)
		await socket.send(json.dumps({"type": "watching", "task": task.id, "count": task.count, "up": len(self.connected())}))
		if self.relay_results:
			for directory, folders, names in os.walk(task.out):
				folders[:] = [folder for folder in folders if not folder.startswith(".")]
				for name in sorted(names):
					await self.relay(task, "results", os.path.relpath(os.path.join(directory, name), task.out), to=socket)
		await task.replay(socket)
		for slot in range(1, task.count + 1):
			if task.unit_over(slot):
				await socket.send(json.dumps({"type": "progress", "task": task.id, "shard": slot, "machine": "", "stage": "done",
					"model": "", "line": "", "quiet": 0, "seconds": 0}))
		if ended and ended[0] is task:
			await socket.send(json.dumps(task.finished_again(ended[1])))
		await self.follow(socket, task)


def local_or_tailnet(host):
	try:
		address = ipaddress.ip_address(host)
	except ValueError:
		return False
	return address.is_loopback or (address.version == 4 and address in TAILNET)


def control_signers(public_key):
	"""An allowed-signers file holding only the session's public key."""
	fields = public_key.split()
	if len(fields) < 2 or not fields[0].startswith("ssh-"):
		sys.exit("--control-key wants a public key such as framework/scripts/coordinator.sh key prints")
	path = os.path.join(tempfile.mkdtemp(prefix="control-key-"), "allowed_signers")
	with open(path, "w") as file:
		file.write(f"{CONTROL_NAMESPACE} {fields[0]} {fields[1]}\n")
	return path
