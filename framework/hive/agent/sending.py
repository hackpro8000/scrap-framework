"""Agent mixin: sending on the live connection, heartbeats with each unit's
stage and quiet time, and a unit's files (big ones in parts)."""
import asyncio
import json
import os
import time

import websockets

from agent.common import HEARTBEAT_SECONDS, PART_BYTES
from agent.machine import free_space, last_line, newest_log
import wire  # noqa: E402


class Sending:
	async def send(self, message):
		"""Sends on whichever connection is live now. session() replaces
		self.socket on every reconnect, so a connection that drops during a
		long step costs a wait, not the result."""
		while True:
			try:
				await self.socket.send(message)
				return
			except websockets.ConnectionClosed:
				await asyncio.sleep(1)

	def begin(self, unit, stage, log, subject="", waiting=False):
		"""A unit starts a stage, writing `log`, working on `subject`. A waiting
		stage waits on other machines and is never quiet (report)."""
		self.activities[unit] = {"stage": stage, "subject": subject, "log": log, "since": time.monotonic(), "waiting": waiting}

	def moved(self, unit):
		"""A send or a step made progress: the stage is not quiet, whatever its log says."""
		work = self.activities.get(unit)
		if work:
			work["moved"] = time.monotonic()

	def report(self, unit, work):
		"""One heartbeat: the stage, the log's last line, how long the log
		has gone without a new one (a long step's line comes only when it
		ends), and the machine's free disk and memory. A waiting stage is
		never quiet: what it waits on is other machines' leases, which the hub
		watches, and their slowness must not get this unit re-dealt as wedged.
		"model" is the wire's name for the stage's subject."""
		now = time.monotonic()
		if work.get("waiting"):
			work["moved"] = now
		seconds = now - work["since"]
		quiet = min(seconds, now - work.get("moved", work["since"]))
		log = newest_log(work["log"])
		try:
			quiet = min(quiet, time.time() - os.path.getmtime(log))
		except OSError:
			pass
		disk, memory = free_space()
		return json.dumps({"type": "progress", "task": unit[0], "shard": unit[1], "stage": work["stage"], "model": work["subject"],
			"line": last_line(log), "quiet": round(quiet), "seconds": round(seconds),
			"disk_gb": disk, "memory_gb": memory})

	async def heartbeat(self, socket):
		try:
			while True:
				await asyncio.sleep(HEARTBEAT_SECONDS)
				for unit, work in list(self.activities.items()):
					await socket.send(self.report(unit, work))
		except websockets.ConnectionClosed:
			pass  # session() ends too; the next connection starts its own

	async def send_file(self, unit, relative, data):
		"""One of a unit's files. A big one goes in parts, each awaited, so a
		heartbeat waits behind one part, never the whole file; the hub joins
		them (Coordinator.join_part). If the connection changes midway, the
		file starts again on the new one."""
		identity, slot = unit
		if len(data) <= PART_BYTES:
			await self.send(wire.pack({"type": "file", "task": identity, "shard": slot, "path": relative, "size": len(data)}, data))
			self.moved(unit)
			return
		while True:
			socket = self.socket
			for offset in range(0, len(data), PART_BYTES):
				await self.send(wire.pack({"type": "file-part", "task": identity, "shard": slot, "path": relative, "offset": offset,
					"size": len(data)}, data[offset:offset + PART_BYTES]))
				self.moved(unit)
				if self.socket is not socket:
					break
			else:
				return
