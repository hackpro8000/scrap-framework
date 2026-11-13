"""The pipeline's build task on the hub (BuildTask), its preview units shared
out between models by cost (share_out), and a lease that remembers the jobs
it claimed (ClaimLease). BuildTask's hooks (units.Task) hand the work to the
plugin (hub_plugin.PipelineHub); unit `slot` is shard <slot> of the build."""
import os
import shutil

from hub_config import RESULTS
from units import Lease, Task


def share_out(asked, count, weights=None):
	"""The preview units of a task of `count` units: one name per unit when
	there are fewer models than units, each model given shares named
	<Name>@<i>@<n> in proportion to its weight (its measured machine-seconds,
	client.py preview_weights), at least one each, summing to count. A name
	ending in "!" is one machine's job whole, for timing a model on its own;
	the "!" is dropped. With as many models as units or more, the names as
	they are, each unit taking every count-th."""
	names = [name.rstrip("!") for name in asked]
	if not names or len(names) >= count:
		return names
	whole = {name[:-1] for name in asked if name.endswith("!")}
	split = [name for name in names if name not in whole]
	if not split:
		return names
	budget = count - (len(names) - len(split))
	weights = weights if isinstance(weights, dict) else {}
	weight = {}
	for name in split:
		given = weights.get(name)
		weight[name] = float(given) if isinstance(given, (int, float)) and not isinstance(given, bool) and given > 0 else 1.0
	total = sum(weight[name] for name in split)
	ideal = {name: budget * weight[name] / total for name in split}
	shares = {name: max(1, int(ideal[name])) for name in split}
	while sum(shares[name] for name in split) > budget:
		name = max((name for name in split if shares[name] > 1), key=lambda name: shares[name] - ideal[name])
		shares[name] -= 1
	while sum(shares[name] for name in split) < budget:
		name = max(split, key=lambda name: ideal[name] - shares[name])
		shares[name] += 1
	units = []
	for name in names:
		count_of = 1 if name in whole else shares[name]
		units += [name] if count_of == 1 else [f"{name}@{i}@{count_of}" for i in range(1, count_of + 1)]
	return units


class ClaimLease(Lease):
	def __init__(self, number, machine):
		super().__init__(number, machine)
		# Jobs it claimed: [(model, kind), job, settled]. Unsettled ones go
		# back to the task when the lease does, so the replacement isn't starved.
		self.claims = []
		# Models whose bakes it has handed over (bakes-pushed, or its preview
		# in): it claims no more of their chunks (hub_previews.bakes_done).
		self.swapped = set()


class BuildTask(Task):
	def __init__(self, pipe, identity, ref, upload, count, previews=(), build=True, weights=None, results=RESULTS):
		super().__init__(identity, count, results)
		self.pipe = pipe  # the PipelineHub that does this task's work
		self.ref, self.upload = ref, upload
		# Without a build the units only render the previews.
		self.build = build
		# Models whose previews the units render, shared out between them by
		# cost (share_out), and the units whose previews haven't all come yet;
		# shares_in counts the shares of each model that have come back.
		self.asked = list(previews)  # as posted, for the tasks file
		self.weights = dict(weights) if isinstance(weights, dict) else {}
		self.previews = [name.rstrip("!") for name in previews]
		self.units = share_out(self.asked, count, self.weights)
		self.shares_in = {}
		self.queues = {}  # (model, bake or render) -> the next job to hand out
		self.returned = {}  # (model, kind) -> jobs a returned lease claimed and never finished
		self.job_answers = {}  # (lease number, claim number) -> job, so a repeated claim gets the same one
		self.bakes = {}  # model -> share number -> commit of that machine's baked textures
		self.bake_commits = {}  # model -> every commit of baked textures pushed, in order
		self.totals = {}  # (model, kind) -> how many jobs there are, as the claims say
		self.published = set()  # models whose preview is out
		self.shown = {}  # model -> the path (or FAILED line) its preview event said, for a session that comes back
		# Units still queued when their model's preview came out: they build, but render nothing.
		self.skipped = set()
		self.previews_waiting = set(range(1, count + 1)) if self.previews else set()
		self.handed = {}  # object id -> (shard, label)
		self.labels = {}  # (shard, object id) -> label, from names.tsv
		self.sent = set()  # objects this task uploaded (the rest had assets)
		self.by_branch = False
		# Objects whose upload has been answered, each counted once however
		# often it is handed over (a re-dealt unit hands over the same ones).
		self.answered = set()

	def text(self, slot=None):
		# When machine 1 uploads, objects go to it through GitHub, not this link.
		hand_over = "branch" if self.by_branch else "coordinator"
		# A unit re-dealt after its build came in only renders.
		build = self.build and slot not in self.done
		return (f"ref={self.ref}\nhand-over={hand_over}\n" + ("" if self.upload else "upload=no\n")
			+ ("" if build else "build=no\n")
			+ (f"preview={','.join(self.units)}\n" if self.units and slot not in self.skipped else ""))

	def share_model(self, slot):
		"""The model a unit is one share of (its preview unit is Name@i@n), or None."""
		unit = self.units[slot - 1] if len(self.units) == self.count and 1 <= slot <= self.count else ""
		return unit.split("@")[0] if "@" in unit else None

	# --- the hooks of units.Task ---

	def unit_over(self, slot):
		return slot in self.done and slot not in self.previews_waiting

	def new_lease(self, number, machine):
		return ClaimLease(number, machine)

	def lease_returning(self, lease):
		# Jobs it claimed and never delivered go to whoever claims next.
		for key, job, settled in lease.claims:
			if not settled:
				self.returned.setdefault(key, []).append(job)
				self.returned[key].sort()

	async def lease_returned(self, lease):
		# After the deal: a replacement already leased is waited for (bakes_done).
		await self.pipe.claims_returned(self, lease)

	def lease_given_back(self, lease):
		# Its own claims come back with it.
		for key, job, settled in lease.claims:
			if not settled and job in self.returned.get(key, []):
				self.returned[key].remove(job)

	def set_aside(self, slot, folder, aside):
		"""merge-shards.sh reads only S*. The objects stay: the uploader may be
		reading them, and the replacement hands over the same ones under the same ids."""
		self.received.pop(slot, None)
		for key in [key for key in self.labels if key[0] == slot]:
			del self.labels[key]
		if not os.path.isdir(folder):
			return
		os.makedirs(aside, exist_ok=True)
		for entry in os.listdir(folder):
			if entry != "handed":
				shutil.move(os.path.join(folder, entry), os.path.join(aside, entry))
				continue
			handed = os.path.join(folder, entry)
			for name in os.listdir(handed):
				if not name.endswith(".glb"):
					os.makedirs(os.path.join(aside, entry), exist_ok=True)
					shutil.move(os.path.join(handed, name), os.path.join(aside, entry, name))

	def takes_file(self, slot, path):
		# A unit re-dealt after its build came in sends only its previews.
		return slot not in self.done or (isinstance(path, str) and path.startswith("previews/"))

	async def file_in(self, slot, name, path, data):
		await self.pipe.file_in(self, slot, name, path, data)

	def relays(self, path):
		# Objects go to the uploader, not the session.
		return not path.endswith(".glb")

	async def finish(self):
		return await self.pipe.finish(self)

	def waiting(self):
		# Kept while previews are still to come; previews_done lets it go.
		return bool(self.previews_waiting)

	def state(self):
		return {**super().state(), "uploads_open": len(self.sent - self.answered), "previews_waiting": len(self.previews_waiting)}

	def saved(self):
		return {"ref": self.ref, "upload": self.upload, "previews": self.asked, "build": self.build,
			"count": self.count, "weights": self.weights, "done": {str(slot): summary for slot, summary in self.done.items()},
			"previews_waiting": sorted(self.previews_waiting)}

	async def replay(self, socket):
		await self.pipe.replay_previews(self, socket)

	def finished_again(self, event):
		# With the previews still waiting now, not when it finished.
		return {**event, "previews_waiting": len(self.previews_waiting)}
