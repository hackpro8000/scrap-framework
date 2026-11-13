"""What the hub tracks: a task cut into units (Task), a unit leased to a
machine (Lease), and a roster entry (Machine).

A plugin's task kind is a subclass of Task. The hook methods below the
bookkeeping are where a kind changes a task's life; the defaults make a
plain task whose unit is over once its machine says done."""
import json
import os
import shutil
import time

from hub_config import RESULTS


class Lease:
	"""One unit held by one machine, from its deal until it is over or comes back."""

	def __init__(self, number, machine):
		self.number, self.machine = number, machine
		self.dealt = self.moved = time.time()


class Machine:
	"""One roster entry: a connection that may drop and come back under the same name."""

	def __init__(self, name, kind):
		self.name, self.kind = name, kind  # kind: github, numbered or worker
		self.socket = None
		self.run = None
		self.closed_at = None
		self.heard = time.time()
		self.hello = {}  # its latest hello, for what plugins read from it
		self.lease = None  # (task id, slot) it holds
		self.cancelling = {}  # (task id, slot) told to stop -> when last told, until it answers idle (or times out)
		self.progress = None  # its latest heartbeat, with the time it came
		self.dropped = set()  # (task id, slot) whose late messages were dropped, logged once
		self.code = None  # the commit its agent runs, from its hello (hub_update)
		self.update_failed = None  # the commit it said it could not update to

	def state(self, now):
		# "shard" is the unit's slot, as the wire names it.
		if self.socket is None:
			return {"name": self.name, "state": "gone", "gone_for": round(now - (self.closed_at or now)),
				"task": self.lease[0] if self.lease else None, "shard": self.lease[1] if self.lease else None}
		if self.lease:
			return {"name": self.name, "state": "unit", "task": self.lease[0], "shard": self.lease[1],
				"heard": round(now - self.heard)}
		return {"name": self.name, "state": "stopping" if self.cancelling else "idle"}


class Task:
	"""A posted task, cut into `count` units. Unit `slot` (1..count) is S<slot>
	in logs and results folders, and "shard" in every message about it."""
	# Its end has been told and it is not written to the tasks file. A kind
	# that a restarted hub should drop sets it from the start.
	completed = False
	# Its units go before every other task's, each to the machine choose() picks.
	chooses = False

	def __init__(self, identity, count, results=RESULTS):
		self.id, self.count = identity, count
		self.queue = list(range(1, count + 1))  # units not leased, front first
		self.leases = {}  # slot -> its Lease
		self.moved_from = {}  # slot -> (machine, reason, its Lease) of a returned lease, until it is dealt again
		# Reloaded after a hub restart: not dealt before this time, so machines
		# still on its units reconnect and get them back first (load_tasks).
		self.held_until = 0
		self.started = time.time()
		self.done = {}  # slot -> summary text
		self.received = {}  # slot -> [files, bytes] it sent, against MAX_UNIT_*
		self.watchers = set()  # control sockets of the session that posted it, for relayed files
		self.out = os.path.join(results, identity)
		os.makedirs(self.out, exist_ok=True)

	# --- hooks a task kind may replace ---

	def text(self, slot):
		"""What a unit is to do: the "task" field of the default message."""
		return ""

	def message(self, slot, lease):
		"""The message that leases unit `slot` to a machine; the lease number
		comes back in the machine's messages, so a cancelled lease's are refused."""
		return json.dumps({"type": "task", "id": self.id, "task": self.text(slot), "shard": slot, "count": self.count,
			"lease": lease.number if lease else 0})

	def choose(self, idle):
		"""With chooses: which of the idle machines takes the next unit, or None to wait."""
		return None

	def unit_over(self, slot):
		"""Whether a unit is over, so its machine is idle again."""
		return slot in self.done

	def new_lease(self, number, machine):
		return Lease(number, machine)

	def lease_returning(self, lease):
		"""A lease goes back to the queue; called before its unit is dealt again."""

	async def lease_returned(self, lease):
		"""A lease went back to the queue and its unit has been dealt again if a machine was free."""

	def lease_given_back(self, lease):
		"""A machine came back for a unit still queued, and has its own lease back."""

	def set_aside(self, slot, folder, aside):
		"""A unit dealt again starts clean: what its folder holds moves to `aside`."""
		self.received.pop(slot, None)
		if not os.path.isdir(folder):
			return
		os.makedirs(aside, exist_ok=True)
		for entry in os.listdir(folder):
			shutil.move(os.path.join(folder, entry), os.path.join(aside, entry))

	def takes_file(self, slot, path):
		"""Whether a file the unit's machine sends (`path` as it named it) is stored."""
		return slot not in self.done

	async def file_in(self, slot, name, path, data):
		"""A unit's file was stored at `path` (`name` inside the unit's folder)."""

	def relays(self, path):
		"""Whether a stored file goes to the task's session (--relay-results)."""
		return True

	async def finish(self):
		"""Every unit is done: wraps the task up and returns its "finished" event."""
		return {"type": "finished", "task": self.id, "out": self.out, "total": round(time.time() - self.started)}

	def waiting(self):
		"""Whether the task stays open after finishing, for work still to come."""
		return False

	def state(self):
		"""What status tells of the task while it is open."""
		return {"age": round(time.time() - self.started), "done": len(self.done), "count": self.count,
			"queued": len(self.queue), "leased": len(self.leases)}

	def saved(self):
		"""Its tasks file entry, which a plugin's loader takes back after a restart."""
		return {"count": self.count, "done": {str(slot): summary for slot, summary in self.done.items()}}

	async def replay(self, socket):
		"""For a session that watches the task again: what it may have missed,
		sent before the units that are over."""

	def finished_again(self, event):
		"""The finished event, as a session that watches the task again is sent it."""
		return event
