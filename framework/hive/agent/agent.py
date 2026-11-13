"""The Agent: its state, the connection to the hub (hello, reading events),
the idle/max clock, and the reconnect loop; the rest is in its mixins. What
a unit is, and every message about one beyond take, cancel and progress,
comes from its plugins (plugins.py)."""
import asyncio
import json
import os
import shutil
import subprocess
import threading
import time

import websockets

from agent import common, machine
from agent.common import ADDRESS_BRANCH, LOST_MINUTES, MAX_MESSAGE, REQUIRED_TOOLS, TUNNEL_ALERT_FAILURES, alert, say
from agent.machine import ensure_tools, http_status, identity_token
from agent.plugins import AgentPlugins
from agent.sending import Sending
from agent.units import Units
from agent.update import Updates, current_commit, lifetime_left
import hive_plugins  # noqa: E402
import wire  # noqa: E402


class Agent(Units, Sending, Updates):
	def __init__(self, url, target, index, count, idle_minutes, max_minutes, plugins=None):
		"""target: the second argument the standby workflow passes, handed on to
		the plugins (what this machine's units work on). plugins: the names of
		the plugins to load; None for game.toml's."""
		self.url, self.target, self.index, self.count = url, target, int(index), int(count)
		self.arguments = [str(url), str(target), str(index), str(count), str(idle_minutes), str(max_minutes)]  # for reexec
		self.published = url == "published"
		self.machine = self.index if self.count == 0 else None
		self.idle_seconds = int(idle_minutes) * 60
		self.stop_at = time.monotonic() + lifetime_left(max_minutes)
		# Hot updates (update.py): the code this process runs, the hub's if different, commits that failed.
		self.code_commit = current_commit()
		self.update_to = None
		self.update_failed = set()
		self.updating = False
		self.idle_until = time.monotonic() + self.idle_seconds
		# A unit is (task id, slot); a machine may do several units of one task.
		self.git_lock = threading.Lock()
		self.handling = set()  # units with a runner still going
		self.cancelling = {}  # unit -> its cancel() while it runs (stop_unit)
		# unit -> {"cancelled": bool, "processes": set of Popen, "lease", "task": its asyncio task}
		self.units = {}
		self.activities = {}  # unit -> what this machine is doing for it (heartbeat() reports them)
		self.stopped = False
		self.failures = 0  # connections in a row that failed or dropped (ALERT TUNNEL_DOWN)
		self.address = url  # the hub address last dialled
		self.socket = None
		self.loop = None
		self.plugins = AgentPlugins(self)
		self.plugins.loaded = hive_plugins.load(self.plugins, plugins)

	def published_address(self):
		# Not through FETCH_HEAD: a task's checkout may be reading it.
		with self.git_lock:
			subprocess.run(["git", "fetch", "-q", "--depth=1", "--no-write-fetch-head", "origin",
				f"+{ADDRESS_BRANCH}:refs/coordinator-address"], check=True, capture_output=True, timeout=60)
			shown = subprocess.run(["git", "show", "refs/coordinator-address:address.json"], check=True, capture_output=True, text=True)
		return json.loads(shown.stdout)["agent"]

	async def session(self):
		token = await asyncio.to_thread(identity_token)
		url = await asyncio.to_thread(self.published_address) if self.published else self.url
		self.address = url
		async with websockets.connect(url, max_size=MAX_MESSAGE, ping_interval=20, ping_timeout=120) as socket:
			# The units still under way, so a restarted hub gives them back; not one being cancelled.
			# "shard" is this machine's number in its run, as the wire names it.
			hello = {"type": "hello", "token": token, "shard": self.index, "count": self.count,
				"units": [list(unit) for unit in self.handling if unit not in self.cancelling], "code": self.code_commit}
			for fields in self.plugins.hello:
				hello.update(fields())
			if self.machine is not None:
				hello["machine"] = self.machine
			await socket.send(json.dumps(hello))
			say(f"connected to {url}")
			self.backoff = 1
			self.socket, self.loop = socket, asyncio.get_running_loop()
			loop = self.loop

			def forward_line(text):
				# say() may run on a plugin's thread.
				loop.call_soon_threadsafe(lambda: asyncio.ensure_future(socket.send(json.dumps({"type": "log", "text": text}))))

			common.forward = forward_line
			if self.failures >= TUNNEL_ALERT_FAILURES:
				alert(f"CLEARED TUNNEL_DOWN: S{self.index} connected to {url} after {self.failures} failures")
			self.failures = 0
			lacking = [tool for tool in REQUIRED_TOOLS if not shutil.which(tool)]
			if lacking:
				say(f"could not find {', '.join(lacking)} on this machine")
			beat = asyncio.create_task(self.heartbeat(socket))
			try:
				async for message in socket:
					if isinstance(message, bytes):
						header, data = wire.unpack(message)
						handler = self.plugins.files.get(header.get("type"))
						if handler:
							await handler(socket, header, data)
						continue
					event = json.loads(message)
					kind = event["type"]
					if kind in self.plugins.units:
						self.take(event)
					elif kind == "cancel":
						self.stop_unit(event)
					elif kind in ("hub", "update"):
						self.want_update(event.get("commit"))
					elif kind == "active":
						# The hub on this machine has work going for others.
						self.idle_until = time.monotonic() + self.idle_seconds
					elif kind == "stop":
						self.stopped = True
						return
					elif kind in self.plugins.messages:
						self.plugins.messages[kind](socket, event)
			finally:
				beat.cancel()

	async def watch_clock(self):
		while not self.stopped:
			now = time.monotonic()
			if now >= self.idle_until or now >= self.stop_at:
				self.stopped = True
				return
			await asyncio.sleep(min(self.idle_until, self.stop_at) - now)

	async def main(self):
		# Out of the environment before any child process can see it.
		machine.WORKER_TOKEN = os.environ.pop("COORDINATOR_WORKER_TOKEN", "")
		# The hub's own; no unit on this machine needs it.
		os.environ.pop("COORDINATOR_WORKER_KEY", None)
		await asyncio.to_thread(ensure_tools)
		self.backoff = 1
		clock = asyncio.create_task(self.watch_clock())
		lost_since = None
		while not self.stopped:
			connection = asyncio.create_task(self.session())
			done, _ = await asyncio.wait({connection, clock}, return_when=asyncio.FIRST_COMPLETED)
			if clock in done:
				connection.cancel()
				break
			error = connection.exception()
			if self.stopped:
				break
			common.forward = None
			if self.backoff == 1:
				lost_since = time.monotonic()
			elif lost_since and not self.published and time.monotonic() - lost_since > LOST_MINUTES * 60:
				say(f"no coordinator for {LOST_MINUTES} minutes; ending to free this machine's slot")
				break
			self.failures += 1
			status = http_status(error)
			answered = f"HTTP {status}" if status else "no HTTP answer"
			say(f"connection lost ({error}; {answered}); retrying in {self.backoff}s")
			if self.failures == TUNNEL_ALERT_FAILURES:
				alert(f"ALERT TUNNEL_DOWN: S{self.index} failed to reach {self.address} {self.failures} times in a row ({answered}: {error}) "
					"| machine 1's tunnel or coordinator is down; if it stays down, start a new run (scripts/standby-start.sh)")
			await asyncio.sleep(self.backoff)
			# A numbered machine waits for the next hub, a minute apart.
			self.backoff = min(60 if self.published else 30, self.backoff * 2)
		say("standby over")
