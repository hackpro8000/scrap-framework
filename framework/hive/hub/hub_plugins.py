"""The hub's side of its plugins (framework/hive/hive_plugins.py loads them):
the `hive` a plugin's register(hive) is given on the hub, one per hub.

Through it a plugin adds handlers for the messages machines send and the
requests sessions send, by kind; loaders that take its tasks back from the
tasks file; hooks on a machine joining and leaving; serve's command-line
options and the setup that reads them. A plugin's task kinds are subclasses
of units.Task, whose hook methods shape a task's life: how a unit is told
and dealt, what happens when its lease comes back, what its files mean, and
how the task finishes."""


class HubPlugins:
	side = "hub"

	def __init__(self, hub):
		self.hub = hub  # the Coordinator
		self.messages = {}  # message kind -> (handler, about a unit, otherwise)
		self.requests = {}  # control request kind -> handler(socket, request)
		self.loaders = []  # load(identity, fields) -> a Task or None
		self.joined = []  # async hook(machine, socket): admitted, before its greeting
		self.left = []  # async hook(machine, socket): its connection is over
		self.options = []  # add(parser): serve's command-line options
		self.setups = []  # setup(settings) -> a coroutine to run beside the hub, or None
		self.notes = []  # what serve's first log line adds, filled by the setups
		self.state = {}  # fields the setups add to the hub's state file
		self.loaded = {}  # plugin name -> what its register returned

	def message(self, kind, handler, unit=True, otherwise=None):
		"""A machine's message of this kind. With unit (the default) it names a
		unit (its "task", "shard" and "lease"): handler(machine, socket, event,
		task, slot, lease) when the machine holds that lease now, else
		otherwise(machine, socket, event), or nothing if otherwise is None.
		With unit=False: handler(machine, socket, event) for every one."""
		self.messages[kind] = (handler, unit, otherwise)

	def request(self, kind, handler):
		"""A session's control request of this kind: handler(socket, request)."""
		self.requests[kind] = handler

	def loader(self, load):
		"""load(identity, fields) -> a Task of the plugin's own, or None when
		the tasks file entry is not one of its kinds wrote (Task.saved)."""
		self.loaders.append(load)

	def on_join(self, hook):
		self.joined.append(hook)

	def on_leave(self, hook):
		self.left.append(hook)

	def option(self, add):
		self.options.append(add)

	def setup(self, start):
		self.setups.append(start)

	def start(self, settings):
		"""Runs every setup with serve's settings (a dict of its options);
		returns the coroutines they want run beside the hub."""
		background = []
		for start in self.setups:
			running = start(settings)
			if running is not None:
				background.append(running)
		return background
