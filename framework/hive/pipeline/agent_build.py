"""PipelineAgent mixin: a build unit ({"type": "task"}): its commit checked
out, framework/scripts/standby-task.sh run as shard <shard> of <count> into
results/<task>-S<shard>/, every file there sent back (the handed-over
objects' names.tsv first), "done", and then the unit's share of the previews."""
import asyncio
import json
import os
import shutil
import subprocess
import time

from agent.common import SCRIPTS, say

FAILED_SUMMARY = "status=FAILED\nbuild=-\nupload=-\ntotal=0\nparts=0\n"


class BuildUnits:
	async def run_build(self, unit, event, work):
		"""The runner of a build unit; True when it ran to its end."""
		agent = self.agent
		text, count = event["task"], event["count"]
		identity, shard = unit
		agent.idle_until = time.monotonic() + agent.idle_seconds
		self.by_branch[identity] = "hand-over=branch" in text
		if unit not in self.built:
			out = os.path.join("results", f"{identity}-S{shard}")
			agent.begin(unit, "build", os.path.join(out, "build.log"))
			try:
				self.built[unit] = await asyncio.to_thread(self.run_task, unit, text, count, out, work)
			except Exception as error:
				# A full disk, say: the coordinator must still hear this unit is over.
				say(f"task {identity} S{shard}: could not run: {error}")
				await agent.send(json.dumps({"type": "done", "task": identity, "shard": shard, "summary": FAILED_SUMMARY}))
				return False
		if work["cancelled"]:
			return False
		await self.send_results(unit, self.built[unit])
		agent.idle_until = time.monotonic() + agent.idle_seconds
		await self.send_previews(unit, text, count, work)
		return True

	def run_task(self, unit, text, count, out, work):
		identity, shard = unit
		# A unit starts clean, whatever an earlier try of it left.
		shutil.rmtree(out, ignore_errors=True)
		os.makedirs(out, exist_ok=True)
		with open(os.path.join(out, "task.txt"), "w") as file:
			file.write(text)
		ref = next((line[4:] for line in text.splitlines() if line.startswith("ref=")), "")
		log = open(os.path.join(out, "build.log"), "w")
		work["checkout"] = True
		ok = self.agent.run_process(work, ["git", "fetch", "-q", "--depth=1", "origin", ref], stdout=log, stderr=log)[0] == 0
		ok = ok and self.agent.run_process(work, ["git", "checkout", "-q", "-f", "FETCH_HEAD"], stdout=log, stderr=log)[0] == 0
		work["checkout"] = False
		log.close()
		if ok:
			code, output = self.agent.run_process(work, [os.path.join(SCRIPTS, "standby-task.sh"), self.agent.target, str(shard), str(count), out],
				stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
			say(f"task {identity} S{shard}: {output.strip()}")
		else:
			with open(os.path.join(out, "summary.txt"), "w") as file:
				file.write(FAILED_SUMMARY)
			say(f"task {identity} S{shard}: could not check out {ref}")
		return out

	async def send_results(self, unit, out):
		identity, shard = unit
		files = []
		for directory, _, names in os.walk(out):
			for name in names:
				path = os.path.join(directory, name)
				relative = os.path.relpath(path, out)
				# In branch mode the objects went to GitHub; only results come back.
				# Previews go on their own afterwards (send_previews).
				if relative == "task.txt" or relative.startswith("previews-run") or (self.by_branch.get(identity) and relative.endswith(".glb")):
					continue
				files.append(relative)
		# Names before objects, so the coordinator knows each object's label.
		files.sort(key=lambda path: (not path.endswith("names.tsv"), path))
		self.agent.begin(unit, "send", os.path.join(out, "build.log"))
		for relative in files:
			with open(os.path.join(out, relative), "rb") as file:
				data = file.read()
			await self.agent.send_file(unit, relative, data)
		summary = open(os.path.join(out, "summary.txt")).read() if os.path.isfile(os.path.join(out, "summary.txt")) else "status=FAILED\n"
		await self.agent.send(json.dumps({"type": "done", "task": identity, "shard": shard, "summary": summary}))
