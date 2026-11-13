#!/usr/bin/env python3
"""The hive's hub: hands units of work to the machines dialled into it the
moment a task is posted, and takes their results back the moment they're
done, all over live connections, so nothing polls. It knows nothing of the
work itself: its plugins (game.toml's hive_plugins, hive_plugins.py) add the
kinds of task, the requests that post them and the messages about them
(hub_plugins.py).

  framework/hive/hub/coordinator.py serve [--agent-host H] [--agent-port P]
                                         [--control-port C] [--control-host H]
                                         [--control-key K] [--relay-results]
                                         [the plugins' options]

Machines (framework/scripts/standby-agent.py) connect to the agent port, proving with
GitHub's identity token that they are this repo's standby machines (oidc.py),
and keep the connection open. The session talks to the control port, which
listens on this machine only (framework/hive/hub/client.py). Both carry JSON
messages; a file is one binary message, its description and bytes together
(wire.py). Everything the machines report, their log lines included, is
written to the hub's log and passed on to the session as it happens.

Every admitted machine joins one roster under a stable name: g<n> for a
GitHub machine of the newest standby run (an older run's are closed),
m<n> for a numbered machine, w<k> for a minted worker. A posted task is cut
into N units (N = machines connected at post, at least 1, unless the
session asks for a number). The hub leases one unit at a time to each idle
machine (by default {"type": "task", "id", "task", "shard", "count",
"lease"}; a task kind may send its own), oldest open task first; a machine
whose unit is over takes the next. A lease comes back to the front of the
queue when its machine's connection has been closed for LEASE_GRACE_SECONDS,
it has sent nothing for LEASE_SILENT_SECONDS, or its unit has not moved for
LEASE_WEDGED_SECONDS; the old holder is sent {"type": "cancel", "task",
"shard"} and is not dealt again until it answers {"type": "idle"}. Anything
it sends for that unit afterwards is dropped. The session sees
{"type": "redealt"} when the unit goes to its new machine.

Each unit sends back its files, into .standby-results/<task>/S<i>/, and then
"done"; once every unit is done the task finishes and the session is told.

If a machine reconnects mid-unit, it is sent its unit again. Its hello names
the units it is still working on, so a restarted hub gives them back to it.
Posted tasks are kept in tasks.json beside the state file until they
complete, so a restarted hub takes them back (through the plugin whose
task kind wrote them); a session that lost its connection asks for its task
again with {"type": "watch-task", "task": id}.

A machine that is not a GitHub one (framework/scripts/cloud-worker.sh) is admitted
by a one-time token: {"type": "mint-workers", "count": n} (signed session
only) makes n tokens, kept in memory only, one live connection per token.
A numbered machine (framework/scripts/cloud-worker.sh join) needs no minting: with
COORDINATOR_WORKER_KEY in the hub's environment, a hello with "machine": n
and "worker:<its lasting token>" (wire.machine_token) is admitted and takes
units at once. GitHub machines are told {"type": "active"} when a task is
posted or a unit finishes, so their idle clocks restart.

With --relay-results (machine 1 with a control key), every file a task
stores also goes to the task's session as one binary message each
({"type": "result-file", "task", "root", "path"}), before "finished"; that
hub runs in a restart loop, so it takes hot updates (hub_update.py).
"""
import argparse
import asyncio
import hmac
import json
import os
import secrets
import sys
import time

import websockets

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# hub_config first: it puts the game's settings (game_settings.py) on the path.
from hub_config import (  # noqa: E402,F401
	CHALLENGE_SECONDS, CONTROL_NAMESPACE, GONE_FORGOTTEN_SECONDS, KEEP_FINISHED, LEASE_GRACE_SECONDS,
	LEASE_SILENT_SECONDS, LEASE_WEDGED_SECONDS, MAX_CONTROL_MESSAGE, MAX_MESSAGE, MAX_SIGNATURE, MAX_UNIT_BYTES,
	MAX_UNIT_FILES, MAX_WORKERS, REPOSITORY, RESULTS, ROOT, STATE, TAILNET, TASK_NAME, TASKS, WORKER_PREFIX, WORKFLOW, say)
import hive_plugins  # noqa: E402
from units import Lease, Machine, Task  # noqa: E402,F401
from hub_plugins import HubPlugins  # noqa: E402
from hub_queue import LeaseQueue  # noqa: E402
from hub_tasks import TaskBook  # noqa: E402
from hub_machines import MachineLinks  # noqa: E402
from hub_session import SessionControl, control_signers, local_or_tailnet  # noqa: E402
from hub_update import HubUpdate, current_commit  # noqa: E402


class Coordinator(LeaseQueue, TaskBook, MachineLinks, SessionControl, HubUpdate):
	def __init__(self, test_without_identity=False, relay_results=False, timeouts=None, worker_key=None, tasks_file=None,
			results=None, plugins=None):
		"""plugins: the names of the plugins to load; None for game.toml's."""
		# Tests point these elsewhere (framework/hive/hub/test_queue.py).
		self.tasks_file = tasks_file or TASKS
		self.results = results or RESULTS
		timeouts = timeouts or {}
		self.grace = float(timeouts.get("grace") or os.environ.get("COORDINATOR_LEASE_GRACE") or LEASE_GRACE_SECONDS)
		self.silent = float(timeouts.get("silent") or os.environ.get("COORDINATOR_LEASE_SILENT") or LEASE_SILENT_SECONDS)
		self.wedged = float(timeouts.get("wedged") or os.environ.get("COORDINATOR_LEASE_WEDGED") or LEASE_WEDGED_SECONDS)
		self.tick = min(1.0, self.grace / 4, self.silent / 4)
		# How long reloaded tasks wait for their machines after a restart: two
		# graces, the longest an agent's reconnect backoff sleeps (60 s).
		self.restart_hold = 2 * self.grace
		self.relay_results = relay_results
		self.test_without_identity = test_without_identity
		self.loop = None
		# The newest GitHub standby run, how new it is, and how many machines it asked for (ALERT SHORT).
		self.run_id = None
		self.run_rank = -1
		self.count = 0
		self.roster = {}  # name -> Machine, in the order they first joined
		self.leases_made = 0
		self.posted = 0  # tasks posted, for unique task ids
		self.tasks = {}  # oldest first: their units are dealt first
		self.watchers = set()  # control websockets waiting on events
		self.control_signers = None  # allowed-signers file, with --control-key
		self.finished = {}  # task id -> (task, its finished event), the last KEEP_FINISHED
		# Minted worker tokens, in memory only: token -> {"name": w<k>, "shard",
		# "count", "socket": its live connection or None}.
		self.workers = {}
		self.minted = 0
		# The key numbered machines' tokens are made from, out of the environment at once.
		self.worker_key = os.environ.pop("COORDINATOR_WORKER_KEY", "")
		if worker_key is not None:
			self.worker_key = worker_key
		self.watchdog = None
		self.hosts = set()  # GitHub machines' connections, to keep their idle clocks going
		# The hub's lifetime, for ALERT LIFETIME (client.py): the job's start
		# (STANDBY_SINCE, so a restart keeps it), the last task activity, and the
		# workflow's limits, which only a hub on machine 1 has.
		self.started = float(os.environ.get("STANDBY_SINCE") or time.time())
		self.last_active = time.time()
		self.idle_minutes = int(os.environ.get("STANDBY_IDLE_MINUTES") or 0) or None
		self.max_minutes = int(os.environ.get("STANDBY_MAX_MINUTES") or 0) or None
		self.run_started = None  # when the newest run's first machine connected (ALERT SHORT)
		self.refused_kinds = set()  # (machine name, kind) of messages no one handles, logged once
		# Last, so a plugin's register sees a whole hub.
		self.plugins = HubPlugins(self)
		self.plugins.loaded = hive_plugins.load(self.plugins, plugins)

	def lifetime(self):
		return {"hub_started": self.started, "last_active": self.last_active,
			"idle_minutes": self.idle_minutes, "max_minutes": self.max_minutes, "now": time.time()}

	def task_states(self):
		"""Per open task, what client.py status needs to tell a stranded one."""
		return {task.id: task.state() for task in self.tasks.values()}

	def connected(self):
		return [machine for machine in self.roster.values() if machine.socket is not None]

	def machines_event(self, machine=None, gone=False):
		connected = self.connected()
		event = {"type": "machine", "up": len(connected), "count": self.count,
			"github_up": sum(1 for each in connected if each.kind == "github" and each.run == self.run_id)}
		if machine:
			event["name"] = machine.name
		if gone:
			event["gone"], event["grace"] = True, self.grace
		return event

	@staticmethod
	def join_part(parts, header, data):
		"""A big file comes in parts (agent/sending.py send_file), kept per
		connection in `parts`; returns the whole file once its last part is
		in, else None. A part out of order drops what was gathered."""
		key = (header.get("task"), header.get("path"))
		offset, size = header.get("offset"), header.get("size")
		if not isinstance(offset, int) or not isinstance(size, int) or size > MAX_MESSAGE:
			parts.pop(key, None)
			return None
		if offset == 0:
			parts[key] = bytearray()
		gathered = parts.get(key)
		if gathered is None or len(gathered) != offset or offset + len(data) > size:
			parts.pop(key, None)
			return None
		gathered += data
		if len(gathered) < size:
			return None
		del parts[key]
		return bytes(gathered)

	def worker(self, token):
		"""The minted record of a worker token, or None. Every token is
		compared, in constant time, so timing tells nothing."""
		found = None
		for minted, record in self.workers.items():
			if hmac.compare_digest(minted.encode(), token.encode()):
				found = record
		return found

	def mint(self, count):
		"""count tokens, each admitting one worker named w<k>. The number and
		count only number the printed lines (client.py mint-workers); a
		worker takes units like any other machine."""
		minted = []
		for number in range(1, count + 1):
			token = secrets.token_hex(32)
			self.minted += 1
			self.workers[token] = {"name": f"w{self.minted}", "shard": number, "count": count, "socket": None}
			minted.append({"shard": number, "count": count, "token": token})
		say(f"minted {count} workers ({', '.join(entry['token'][:6] for entry in minted)}...)")
		return f"w{self.minted - count + 1}-w{self.minted}", minted

	async def keep_hosts_awake(self):
		self.last_active = time.time()
		for socket in list(self.hosts):
			try:
				await socket.send(json.dumps({"type": "active"}))
			except Exception:
				self.hosts.discard(socket)


async def serve(coordinator, arguments):
	if arguments.test_without_identity and arguments.agent_host != "127.0.0.1":
		sys.exit("--test-without-identity is only for a local run (agent host 127.0.0.1)")
	coordinator.test_without_identity, coordinator.relay_results = arguments.test_without_identity, arguments.relay_results
	# The plugins read their options (and may refuse them) before anything is served.
	background = coordinator.plugins.start(vars(arguments))
	coordinator.loop = asyncio.get_running_loop()
	# The code this process loaded, and whether a loop restarts it (hub_update).
	coordinator.code_commit, coordinator.restarts = current_commit(), arguments.relay_results
	coordinator.load_tasks()
	if arguments.control_key:
		coordinator.control_signers = control_signers(arguments.control_key)
	elif not local_or_tailnet(arguments.control_host):
		sys.exit("--control-host off this machine and the tailnet needs --control-key")
	# A ping waits behind whatever a machine is sending, and the tunnel is
	# slow, so a big result could outlast websockets' 20 s and drop the machine.
	agents = await websockets.serve(coordinator.agent, arguments.agent_host, arguments.agent_port, max_size=MAX_MESSAGE,
		ping_interval=20, ping_timeout=120)
	control = await websockets.serve(coordinator.control, arguments.control_host, arguments.control_port, max_size=MAX_CONTROL_MESSAGE)
	os.makedirs(os.path.dirname(STATE), exist_ok=True)
	control_host = f"[{arguments.control_host}]" if ":" in arguments.control_host else arguments.control_host
	state = {"pid": os.getpid(), "control": f"ws://{control_host}:{arguments.control_port}",
		"agent_port": arguments.agent_port, "agent_host": arguments.agent_host, **coordinator.plugins.state}
	if os.path.isfile(STATE):
		try:
			old = json.load(open(STATE))
			if "agent_url" in old and old.get("pid") == os.getpid():
				state["agent_url"] = old["agent_url"]
		except Exception:
			pass
	with open(STATE, "w") as file:
		json.dump(state, file)
	say(f"machines on {arguments.agent_host}:{arguments.agent_port}, control on {arguments.control_host}:{arguments.control_port}"
		+ "".join(coordinator.plugins.notes)
		+ (" (results relayed)" if arguments.relay_results else "")
		+ (" (control needs the key)" if arguments.control_key else ""))
	await asyncio.gather(agents.wait_closed(), control.wait_closed(), *background)


def main():
	# The plugins are loaded first: they add serve's options of their own.
	coordinator = Coordinator()
	parser = argparse.ArgumentParser()
	parser.add_argument("command", choices=["serve"])
	parser.add_argument("--agent-host", default="127.0.0.1")
	parser.add_argument("--agent-port", type=int, default=8765)
	# Machine 1 puts control on its tailnet address so a session can attach.
	parser.add_argument("--control-host", default="127.0.0.1")
	parser.add_argument("--control-port", type=int, default=8766)
	# Required off this machine and the tailnet (a tunnel): the one public
	# key whose signature admits a control connection.
	parser.add_argument("--control-key", default="")
	# Local tests only: agents may connect with the token "test". Never with
	# a tunnel, which makes every outside connection look local.
	parser.add_argument("--test-without-identity", action="store_true")
	# Results go back over the control link to the session that posted the task.
	parser.add_argument("--relay-results", action="store_true")
	for add in coordinator.plugins.options:
		add(parser)
	asyncio.run(serve(coordinator, parser.parse_args()))


if __name__ == "__main__":
	main()
