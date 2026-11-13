"""Agent mixin: a leased unit's life: taking it, running it through the
runner its plugin registered for its kind (AgentPlugins.unit), and
cancelling it."""
import asyncio
import json
import os
import shutil
import subprocess

from agent.common import say
from agent.machine import kill_tree


class Units:
	@staticmethod
	def run_process(work, command, **options):
		"""Runs one of a unit's processes in its own session, so cancel() can
		kill it with everything under it. Returns (exit code, stdout)."""
		if work["cancelled"]:
			return -9, ""
		process = subprocess.Popen(command, start_new_session=True, **options)
		work["processes"].add(process)
		try:
			output, _ = process.communicate()
		finally:
			work["processes"].discard(process)
		return process.returncode, output or ""

	def take(self, event):
		"""A unit leased by the hub. One already under way (sent again after a
		reconnect) carries on, under the lease number it is sent now, and
		answers on the new connection. One whose cancel is still running
		starts once the cancel is over."""
		run, accepts = self.plugins.units[event["type"]]
		if accepts and not accepts(event):
			return
		unit = (event["id"], event["shard"])
		stopping = self.cancelling.get(unit)
		if stopping:
			asyncio.create_task(self.take_after(stopping, event))
			return
		if unit in self.handling:
			if unit in self.units:
				self.units[unit]["lease"] = event.get("lease")
			return
		self.handling.add(unit)
		work = self.units[unit] = {"cancelled": False, "processes": set(), "lease": event.get("lease")}
		work["task"] = asyncio.create_task(self.run_unit(run, unit, event, work))

	async def take_after(self, stopping, event):
		# wait(), not await: this waiter's own end must not cancel the cancel.
		await asyncio.wait({stopping})
		self.take(event)

	async def run_unit(self, run, unit, event, work):
		"""A unit from its start to its end; a normal end is reported as its stage done."""
		ended = False
		try:
			ended = await run(unit, event, work)
		finally:
			self.activities.pop(unit, None)
			self.handling.discard(unit)
			if self.units.get(unit) is work:
				self.units.pop(unit, None)
			# Also on an early end; a no-op if the call below already started it.
			asyncio.get_running_loop().call_soon(self.update_if_due)
		if ended:
			# "model" is the wire's name for what a stage works on.
			await self.send(json.dumps({"type": "progress", "task": unit[0], "shard": unit[1], "stage": "done", "model": "", "line": "",
				"quiet": 0, "seconds": 0}))
		# A hot update waits for the unit to end (update.py).
		self.update_if_due()

	def stop_unit(self, event):
		"""A cancel from the hub, run beside the connection's reading and kept
		in self.cancelling until it is over, so take() can wait for it."""
		unit = (event.get("task"), event.get("shard"))
		if not isinstance(unit[0], str) or not isinstance(unit[1], int) or unit in self.cancelling:
			return
		stopping = self.cancelling[unit] = asyncio.create_task(self.cancel(event))
		stopping.add_done_callback(lambda done: self.cancelling.pop(unit, None) if self.cancelling.get(unit) is done else None)

	async def cancel(self, event):
		"""The hub took a unit back: kill its processes, drop what it made
		(results/<task>-S<slot>), and say this machine is idle. Answered even
		for a unit this machine never had (it may have restarted since)."""
		unit = (event.get("task"), event.get("shard"))
		work = self.units.get(unit)
		if work:
			work["cancelled"] = True
			for process in list(work["processes"]):
				kill_tree(process.pid)
			running = work.get("task")
			if running and not running.done():
				running.cancel()
				try:
					await running
				except BaseException:
					pass
			if work.get("checkout") and os.path.exists(os.path.join(".git", "index.lock")):
				# A checkout killed midway leaves its lock; the next unit's would fail.
				os.remove(os.path.join(".git", "index.lock"))
			say(f"task {unit[0]} S{unit[1]}: cancelled by the coordinator")
		self.handling.discard(unit)
		self.activities.pop(unit, None)
		if self.units.get(unit) is work:
			self.units.pop(unit, None)
		for cancelled in self.plugins.cancelled:
			cancelled(unit)
		if isinstance(unit[0], str) and isinstance(unit[1], int):
			shutil.rmtree(os.path.join("results", f"{unit[0]}-S{unit[1]}"), ignore_errors=True)
		await self.send(json.dumps({"type": "idle", "task": unit[0], "shard": unit[1]}))
		self.update_if_due()
