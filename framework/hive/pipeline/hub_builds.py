"""Build tasks on the hub (a part of PipelineHub): `build` from a session,
posting and reloading them, the handed-over objects among a unit's files,
and the task's end: uploads waited for, uploaded.tsv and summary.txt
written, and the results merged into the game's tables
(framework/scripts/merge-shards.sh)."""
import asyncio
import json
import os
import subprocess
import time

from hub_config import ROOT, SCRIPTS, TASK_NAME, say
from pipeline.build_task import BuildTask


class Builds:
	async def build_request(self, socket, request):
		"""A session's build: the task is posted, the session told its id and
		units, and only then dealt; the connection then follows the task."""
		hub = self.hub
		previews = request.get("previews", [])
		if not isinstance(request.get("ref"), str) or not isinstance(previews, list) or not all(isinstance(name, str) for name in previews):
			await socket.send(json.dumps({"type": "error", "text": "a build wants a ref and a list of preview names"}))
			return
		upload, build = bool(request.get("upload", True)), bool(request.get("build", True))
		refused = self.refusal(upload, build)
		if refused:
			say(f"build of {request['ref'][:12]} refused: {refused}")
			await socket.send(json.dumps({"type": "error", "text": refused}))
			return
		identity = hub.new_task_id("t")
		hub.watchers.add(socket)
		# Previews alone hand nothing over; with uploads off nothing is asked to upload.
		task = await self.post(identity, request["ref"], upload and not self.uploads_off, previews,
			build, request.get("units"), request.get("weights"))
		task.watchers.add(socket)
		event = hub.machines_event()
		await socket.send(json.dumps({"type": "posted", "task": identity, "count": task.count, "up": event["up"],
			"github_up": event["github_up"], "run_count": hub.count, "units": task.units, "relayed": hub.relay_results,
			"lease_seconds": {"grace": hub.grace, "silent": hub.silent, "wedged": hub.wedged}, **hub.lifetime()}))
		# Dealt only now, so nothing about the task reaches the session before its id.
		await hub.deal()
		await hub.follow(socket, task)

	async def post(self, identity, ref, upload, previews=(), build=True, units=None, weights=None):
		"""Cuts a build into units (as many as machines are connected, unless
		asked) and queues them; the caller deals them once the session knows the id."""
		hub = self.hub
		count = hub.unit_count(units)
		task = BuildTask(self, identity, ref, upload, count, previews, build, weights, hub.results)
		task.by_branch = self.uploads_on_machine
		await hub.add_task(task)
		say(f"task {identity}: {count} units for {len(hub.connected())} machines" + (f", previews {','.join(task.units)}" if task.units else ""))
		return task

	def load_task(self, identity, fields):
		"""A build a previous hub left in the tasks file (BuildTask.saved), or None."""
		if not self.task_entry_fits(identity, fields):
			return None
		refused = self.refusal(fields["upload"], fields.get("build", True))
		if refused:
			say(f"task {identity} not taken back: {refused}")
			return None
		task = BuildTask(self, identity, fields["ref"], fields["upload"], fields["count"], fields.get("previews", []), fields.get("build", True),
			fields.get("weights"), self.hub.results)
		task.by_branch = self.uploads_on_machine
		for slot, summary in (fields.get("done") or {}).items():
			if str(slot).isdigit() and 1 <= int(slot) <= task.count and isinstance(summary, str):
				task.done[int(slot)] = summary
		waiting = fields.get("previews_waiting")
		if task.previews and isinstance(waiting, list):
			task.previews_waiting = {slot for slot in waiting if isinstance(slot, int) and 1 <= slot <= task.count}
		return task

	@staticmethod
	def task_entry_fits(identity, fields):
		"""Whether a tasks file entry has the shape BuildTask.saved writes."""
		return (TASK_NAME.fullmatch(identity) is not None and isinstance(fields, dict)
			and isinstance(fields.get("ref"), str) and isinstance(fields.get("upload"), bool)
			and isinstance(fields.get("count"), int) and not isinstance(fields.get("count"), bool) and fields["count"] >= 1
			and isinstance(fields.get("previews", []), list) and all(isinstance(name, str) for name in fields.get("previews", []))
			and isinstance(fields.get("build", True), bool) and isinstance(fields.get("weights") or {}, dict)
			and isinstance(fields.get("done") or {}, dict) and isinstance(fields.get("previews_waiting") or [], list))

	async def file_in(self, task, shard, name, path, data):
		"""A unit's stored file: its handed-over objects' names, the commit
		they were pushed to, or an object itself, which goes to the uploader."""
		if name == os.path.join("handed", "names.tsv"):
			for line in data.decode().splitlines():
				if "\t" in line:
					identity, label = line.split("\t", 1)
					task.labels[(shard, identity)] = label
		elif name == "handed-commit.txt" and task.by_branch and task.upload:
			await self.hand_to_machine_one(task, shard, data.decode().strip())
		elif name.startswith("handed" + os.sep) and name.endswith(".glb") and task.upload:
			identity = os.path.basename(name)[:-4]
			label = task.labels.get((shard, identity), identity)
			if identity not in task.handed:
				task.handed[identity] = (shard, label)
			if self.uploads_on_machine:
				self.uploader.sent_paths[identity] = (identity, path, label, shard)
			if self.uploader.add(identity, path, label, shard):
				task.sent.add(identity)
				say(f"task {task.id}: uploading {label} ({identity}) from S{shard}")
				await self.hub.emit({"type": "uploading", "task": task.id, "object": identity, "label": label, "queued": len(task.sent)})

	async def finish(self, task):
		"""Every shard is built: waits for the uploads, writes uploaded.tsv and
		summary.txt, pushes or relays them, merges, and returns the finished event."""
		hub = self.hub
		built = time.time() - task.started
		if self.uploads_on_machine:
			await self.uploader.wait_async(list(task.handed))
		else:
			await asyncio.to_thread(self.uploader.wait, list(task.handed))
		self.uploader.finish()
		failed = {i: e for i, e in self.uploader.failed.items() if i in task.handed}
		with open(os.path.join(task.out, "uploaded.tsv"), "w") as file:
			for identity, (shard, _label) in task.handed.items():
				asset = self.uploader.asset_of(identity)
				if asset:
					file.write(f"{identity}\t{asset}\t{shard}\n")
		with open(os.path.join(task.out, "summary.txt"), "w") as file:
			file.write(f"built={round(built)}\ntotal={round(time.time() - task.started)}\nobjects={len(task.handed)}\n"
				f"uploaded={len(task.sent & set(self.uploader.record))}\nfailed={len(failed)}\n")
		if self.git_link:
			await asyncio.to_thread(self.push_results, task)
		await hub.relay(task, "results", "uploaded.tsv")
		await hub.relay(task, "results", "summary.txt")
		merged = None
		# Fake uploads must never reach the game's tables.
		mergeable = task.upload and not failed and not self.dry and not self.uploads_off and not hub.test_without_identity
		if mergeable and not self.git_link and not hub.relay_results:
			merged = await asyncio.to_thread(self.merge, task)
		# Relayed: the session has the files and merges them itself (merge_here).
		return {"type": "finished", "task": task.id, "out": task.out, "built": round(built),
			"total": round(time.time() - task.started), "objects": len(task.handed), "uploaded": len(task.sent & set(self.uploader.record)), "failed": failed,
			"width": round(self.uploader.throttle.limit, 1), "merged": merged, "previews_waiting": len(task.previews_waiting),
			"relayed": hub.relay_results, "merge_here": bool(mergeable and hub.relay_results), "layout": self.layout}

	def merge(self, task):
		"""Merges a finished task into the game's tables (framework/scripts/merge-shards.sh)
		and returns the asset ids that are new, which need the game's
		permission; or the merge's error."""
		shards = sorted(os.path.join(task.out, name) for name in os.listdir(task.out) if name.startswith("S"))
		result = subprocess.run([os.path.join(SCRIPTS, "merge-shards.sh"), self.layout, *shards], cwd=ROOT, capture_output=True, text=True)
		if result.returncode != 0:
			say(f"task {task.id}: merge failed: {result.stderr.strip()[-300:]}")
			return {"error": result.stderr.strip()[-300:]}
		new = [line for line in result.stdout.split() if line.isdigit()]
		say(f"task {task.id}: merged; {len(new)} new assets need the game's permission")
		return {"new_assets": new}
