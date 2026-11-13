"""The pull queue: dealing units to idle machines, leases, taking them
back and dealing them again (a part of Coordinator)."""
import asyncio
import json
import os
import time
import traceback

from hub_config import GONE_FORGOTTEN_SECONDS, say


class LeaseQueue:
	# --- the queue ---

	async def send_to(self, machine, message):
		"""Sends to a machine if it is connected; a dropped one hears it again
		when it reconnects (its lease, its cancels)."""
		if machine.socket is None:
			return
		try:
			await machine.socket.send(message)
		except Exception:
			pass

	def unit_message(self, task, slot):
		return task.message(slot, task.leases.get(slot))

	async def tell_cancel(self, machine, task_id, slot):
		machine.cancelling[(task_id, slot)] = time.time()
		await self.send_to(machine, json.dumps({"type": "cancel", "task": task_id, "shard": slot}))

	def idle_machines(self):
		"""Connected, holding nothing, every cancel answered, and on the hub's code (hub_update)."""
		return [machine for machine in self.roster.values() if machine.socket is not None and not machine.lease
			and not machine.cancelling and not self.stale(machine)]

	async def deal(self):
		"""Leases the front queued unit of the oldest open task to each idle
		machine. A task reloaded after a restart waits out its hold. Tasks
		whose kind chooses its machines (Task.chooses) go first, each unit to
		the idle machine the task picks."""
		for task in [task for task in self.tasks.values() if task.chooses and task.queue]:
			machine = task.choose(self.idle_machines())
			if machine:
				await self.grant(machine, task, task.queue.pop(0))
		now = time.time()
		for machine in list(self.roster.values()):
			if machine.socket is None or machine.lease or machine.cancelling or self.stale(machine):
				continue
			task = next((task for task in self.tasks.values() if task.queue and task.held_until <= now and not task.chooses), None)
			if not task:
				return
			await self.grant(machine, task, task.queue.pop(0))

	async def grant(self, machine, task, slot):
		"""A new lease of a unit already taken off the queue. A unit taken
		back from a machine starts clean here, when it is dealt again."""
		moved = task.moved_from.pop(slot, None)
		if moved and slot not in task.done:
			try:
				self.clear_unit(task, slot, moved[2].number)
			except Exception:
				# Left in place rather than lose the unit.
				say(f"task {task.id}: could not move S{slot}'s old results aside:\n{traceback.format_exc()}")
		self.leases_made += 1
		lease = task.new_lease(self.leases_made, machine.name)
		# Leased before anything is awaited: a unit is never seen neither queued
		# nor leased (a plugin may ask who still holds what).
		await self.lease_to(machine, task, slot, lease)
		if moved:
			say(f"task {task.id}: S{slot} re-dealt from {moved[0]} to {machine.name}: {moved[1]}")
			await self.emit({"type": "redealt", "task": task.id, "shard": slot, "from": moved[0], "to": machine.name, "reason": moved[1]})

	async def lease_to(self, machine, task, slot, lease):
		task.leases[slot] = lease
		machine.lease = (task.id, slot)
		machine.dropped.discard((task.id, slot))
		# A unit it was told to stop and now holds again is owed no cancel.
		machine.cancelling.pop((task.id, slot), None)
		await self.send_to(machine, self.unit_message(task, slot))

	async def give_back(self, machine, task, slot):
		"""A machine reconnected still on a queued unit (its lease taken back
		after the grace, or the hub restarted): it keeps the unit, with no
		cancel. Its own returned lease comes back whole."""
		moved = task.moved_from.get(slot)
		if not moved or moved[0] != machine.name:
			say(f"task {task.id}: {machine.name} is still on S{slot}; it keeps it")
			await self.grant(machine, task, slot)
			return
		del task.moved_from[slot]
		lease = moved[2]
		task.lease_given_back(lease)
		lease.moved = time.time()
		say(f"task {task.id}: {machine.name} came back still on S{slot}; its lease is given back")
		await self.lease_to(machine, task, slot, lease)

	async def unit_over(self, task, slot):
		"""Once a unit is over (Task.unit_over), its machine is idle."""
		if not task.unit_over(slot):
			return
		lease = task.leases.pop(slot, None)
		if not lease:
			return
		machine = self.roster.get(lease.machine)
		if machine and machine.lease == (task.id, slot):
			machine.lease = None
		# A progress event as the agents send them ("model" is the wire's name for what a stage works on).
		await self.emit({"type": "progress", "task": task.id, "shard": slot, "machine": lease.machine, "stage": "done",
			"model": "", "line": "", "quiet": 0, "seconds": round(time.time() - lease.dealt)})
		await self.deal()

	def lease_lost(self, machine, lease, now):
		"""Why a lease goes back to the queue now, or None while it holds."""
		if machine is None:
			return "its machine left the roster"
		if machine.socket is None:
			gone = now - (machine.closed_at or now)
			return f"connection closed for {gone:.0f}s" if gone >= self.grace else None
		heard = now - max(machine.heard, lease.dealt)
		if heard >= self.silent:
			return f"no heartbeat for {heard:.0f}s"
		quiet = now - lease.moved
		if quiet >= self.wedged:
			return f"wedged: its log quiet for {quiet:.0f}s"
		return None

	async def redeal(self, task, slot, reason):
		"""Puts a leased unit back at the front of the queue, tells its old
		holder to stop, and deals it again."""
		lease = task.leases.pop(slot, None)
		if not lease:
			return
		# Queued first, so nothing below can leave it neither queued nor leased.
		# Its folder is cleared when it is dealt again (grant), not here: its
		# machine may come back for it (give_back).
		task.queue.insert(0, slot)
		task.moved_from[slot] = (lease.machine, reason, lease)
		task.lease_returning(lease)
		machine = self.roster.get(lease.machine)
		if machine and machine.lease == (task.id, slot):
			machine.lease = None
			await self.tell_cancel(machine, task.id, slot)
		say(f"task {task.id}: S{slot} taken back from {lease.machine}: {reason}")
		await self.deal()
		# After the deal, so the task sees whether a replacement was dealt.
		await task.lease_returned(lease)

	def clear_unit(self, task, slot, lease_number):
		"""A re-dealt unit starts clean: what its folder holds moves aside to
		.redealt/ (Task.set_aside; the relay skips dot folders)."""
		folder = os.path.join(task.out, f"S{slot}")
		aside = os.path.join(task.out, ".redealt", f"S{slot}-L{lease_number}")
		task.set_aside(slot, folder, aside)

	async def watch_leases(self):
		"""Takes back leases whose machines are gone, silent or wedged, drops
		cancels never answered, ends restart holds, and forgets machines long
		gone that hold nothing."""
		while True:
			await asyncio.sleep(self.tick)
			try:
				now = time.time()
				freed = False
				for task in list(self.tasks.values()):
					for slot, lease in list(task.leases.items()):
						reason = self.lease_lost(self.roster.get(lease.machine), lease, now)
						if reason:
							await self.redeal(task, slot, reason)
					if task.held_until and now >= task.held_until:
						task.held_until, freed = 0, True
				for machine in list(self.roster.values()):
					for key, since in list(machine.cancelling.items()):
						# Heard from since, yet no idle for the silent limit: the answer is not coming.
						if machine.socket is not None and machine.heard > since and now - since >= self.silent:
							del machine.cancelling[key]
							freed = True
							say(f"{machine.name} never answered the cancel of S{key[1]} of {key[0]}; taken as idle")
					if machine.socket is None and not machine.lease and now - (machine.closed_at or now) >= GONE_FORGOTTEN_SECONDS:
						del self.roster[machine.name]
				if freed:
					await self.deal()
			except Exception:
				say(f"lease watch failed:\n{traceback.format_exc()}")
