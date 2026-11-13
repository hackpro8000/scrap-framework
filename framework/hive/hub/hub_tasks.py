"""Tasks from post to finish: the tasks file, events to the session, relayed
files, units done and the task's end (a part of Coordinator). What a task
does at its end is its kind's (Task.finish)."""
import asyncio
import json
import os
import time

import websockets

import wire
from hub_config import KEEP_FINISHED, MAX_WORKERS, ROOT, TASK_NAME, say


class TaskBook:
	def save_tasks(self):
		"""Writes the tasks not yet completed to the tasks file, each as its
		kind saves it (Task.saved), so a restart does not do their done units again."""
		open_tasks = {task.id: task.saved() for task in self.tasks.values() if not task.completed}
		os.makedirs(os.path.dirname(self.tasks_file), exist_ok=True)
		with open(self.tasks_file + ".new", "w") as file:
			json.dump(open_tasks, file)
		os.replace(self.tasks_file + ".new", self.tasks_file)

	def load_tasks(self):
		"""Takes back the tasks a previous hub left open, through the first
		plugin loader that knows the entry, every unit not over queued but held
		for restart_hold: a machine that reconnects names the units it is still
		on and gets them back (greet) before any is dealt. Never raises: a bad
		file or entry is logged and skipped."""
		try:
			if not os.path.isfile(self.tasks_file):
				return
			open_tasks = json.load(open(self.tasks_file))
			if not isinstance(open_tasks, dict):
				say(f"ignoring a tasks file that is not an object: {type(open_tasks).__name__}")
				return
			for identity, fields in open_tasks.items():
				task = None
				if TASK_NAME.fullmatch(identity) and isinstance(fields, dict):
					task = next((task for task in (load(identity, fields) for load in self.plugins.loaders) if task), None)
				if task is None:
					say(f"skipping a bad tasks file entry: {str(identity)[:40]!r}")
					continue
				task.queue = [slot for slot in task.queue if not task.unit_over(slot)]
				task.held_until = time.time() + self.restart_hold
				self.tasks[identity] = task
				say(f"task {identity} taken back from the tasks file, {len(task.done)} of {task.count} units done")
		except Exception as error:
			say(f"ignoring an unreadable tasks file: {error}")

	def new_task_id(self, prefix):
		"""A task id no other task of this hub has: <prefix><time>-<pid>-<n>."""
		self.posted += 1
		return f"{prefix}{int(time.time())}-{os.getpid()}-{self.posted}"

	def unit_count(self, asked):
		"""How many units a new task is cut into: as asked, or one per machine connected."""
		if isinstance(asked, int) and not isinstance(asked, bool) and 1 <= asked <= MAX_WORKERS * 4:
			return asked
		return max(1, len(self.connected()))

	async def add_task(self, task):
		"""Opens a posted task; the caller deals it (deal) once the session knows its id."""
		self.tasks[task.id] = task
		self.save_tasks()
		await self.keep_hosts_awake()

	async def follow(self, socket, task):
		"""Keeps a session's connection on a task until the session hangs up."""
		try:
			async for _ in socket:
				pass
		except websockets.ConnectionClosed:
			pass
		finally:
			self.watchers.discard(socket)
			task.watchers.discard(socket)

	async def emit(self, event):
		message = json.dumps(event)
		for watcher in list(self.watchers):
			try:
				await watcher.send(message)
			except Exception:
				self.watchers.discard(watcher)

	async def relay(self, task, root, path, data=None, to=None):
		"""With --relay-results, sends one stored file to the task's session
		(or only to the socket `to`), unless its kind keeps it back
		(Task.relays). root is "results" (path under task.out) or "repo"
		(path under ROOT, the game's folder)."""
		if not self.relay_results or not task.relays(path):
			return
		if data is None:
			with open(os.path.join(task.out if root == "results" else ROOT, path), "rb") as file:
				data = file.read()
		message = wire.pack({"type": "result-file", "task": task.id, "root": root, "path": path}, data)
		for watcher in [to] if to else list(task.watchers):
			try:
				await watcher.send(message)
			except Exception:
				task.watchers.discard(watcher)

	async def unit_done(self, task, slot, event, machine=""):
		"""A unit's machine said done ("summary" its result)."""
		if slot in task.done:
			return
		summary = event.get("summary", "")
		task.done[slot] = summary if isinstance(summary, str) else ""
		self.save_tasks()
		say(f"task {task.id}: S{slot} done by {machine} ({len(task.done)} of {task.count}): {task.done[slot].strip().replace(chr(10), ' ')}")
		# "shard" is the wire's name for a unit's result event.
		await self.emit({"type": "shard", "task": task.id, "shard": slot, "machine": machine, "summary": task.done[slot],
			"seconds": round(time.time() - task.started)})
		await self.keep_hosts_awake()
		if len(task.done) >= task.count:
			asyncio.create_task(self.complete(task))
		await self.unit_over(task, slot)

	async def complete(self, task):
		"""Every unit is done: the task's kind wraps it up (Task.finish), the
		session is told, and the task closes unless its kind still waits."""
		event = await task.finish()
		self.finished[task.id] = (task, event)
		for old in list(self.finished)[:-KEEP_FINISHED]:
			del self.finished[old]
		await self.emit(event)
		# Kept while its kind still waits (Task.waiting); the kind lets it go.
		task.completed = True
		self.save_tasks()
		if not task.waiting():
			self.tasks.pop(task.id, None)
