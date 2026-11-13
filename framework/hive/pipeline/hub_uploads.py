"""Uploads on the hub (a part of PipelineHub): objects go to the uploader
(uploader.py here, or remote_uploader.py when build machine 1 uploads with
--uploads-on-machine), and each answer is told to the tasks that handed
the object over."""
import asyncio
import json
import os

from hub_config import say
from pipeline.build_task import BuildTask


class Uploads:
	async def machine_joined(self, machine, socket):
		"""A worker has no Roblox key; only a GitHub machine 1 uploads."""
		if not (self.uploads_on_machine and machine.name == "g1"):
			return
		width = known = None
		if os.path.isfile(self.uploader.width_path):
			try:
				fields = [float(field) for field in open(self.uploader.width_path).read().split()]
				width, known = fields[0], fields[1] if len(fields) > 1 else None
			except (ValueError, IndexError):
				pass
		await socket.send(json.dumps({"type": "uploader", "layout": self.layout, "width": width, "known": known}))
		await self.uploader.connected(socket)

	async def machine_left(self, machine, socket):
		if not (self.uploads_on_machine and self.uploader.agent is socket):
			return
		self.uploader.agent = None
		if self.uploader.pending:
			await self.hub.emit({"type": "warning", "text": f"machine 1 dropped with {len(self.uploader.pending)} uploads unanswered; they go again when it reconnects"})

	async def machine_uploaded(self, machine, socket, event):
		"""Machine 1's answer for one object it uploaded."""
		if not self.uploads_on_machine:
			return
		self.uploader.answered(event)
		await self.uploaded(event["id"], event.get("asset"), event.get("error"))

	async def hand_to_machine_one(self, task, shard, commit):
		"""A builder pushed its objects to its branch: queue them and tell
		machine 1 to fetch that commit and upload them."""
		wanted = {}
		for (from_shard, identity), label in task.labels.items():
			if from_shard != shard:
				continue
			if identity not in task.handed:
				task.handed[identity] = (shard, label)
			if self.uploader.track(identity):
				task.sent.add(identity)
				wanted[identity] = label
		if not wanted:
			return
		say(f"task {task.id}: S{shard} pushed {len(wanted)} objects at {commit[:8]}; machine 1 fetches them")
		await self.hub.emit({"type": "uploading", "task": task.id, "shard": shard, "count": len(wanted), "queued": len(task.sent)})
		await self.uploader.request_fetch({"type": "fetch-objects", "task": task.id, "shard": shard, "commit": commit, "ids": wanted})

	def local_answer(self, identity, asset, error):
		"""From the local uploader's threads."""
		loop = self.hub.loop
		if loop:
			loop.call_soon_threadsafe(lambda: asyncio.ensure_future(self.uploaded(identity, asset, error)))

	async def uploaded(self, identity, asset, error):
		if error:
			say(f"upload of {identity} failed: {error}")
		for task in list(self.hub.tasks.values()):
			# Once per object: machine 1 answers again for one handed over twice.
			if isinstance(task, BuildTask) and identity in task.handed and identity not in task.answered:
				task.answered.add(identity)
				await self.hub.emit({"type": "uploaded", "task": task.id, "object": identity, "label": task.handed[identity][1],
					"asset": asset, "error": error, "done": len(task.answered), "of": len(task.sent)})
