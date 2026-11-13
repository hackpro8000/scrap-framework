"""The agent's side of the hive's plugins (framework/hive/hive_plugins.py
loads them): the `hive` a plugin's register(hive) is given on a machine, one
per Agent. Through it a plugin adds the runners of its units, by the kind of
message that leases them; handlers for its other messages from the hub;
fields of the hello; and a hook on a unit being cancelled."""


class AgentPlugins:
	side = "agent"

	def __init__(self, agent):
		self.agent = agent  # the Agent
		self.units = {}  # kind of unit message -> (run, accepts)
		self.messages = {}  # other message kind -> handler(socket, event)
		self.files = {}  # binary message kind -> async handler(socket, header, data)
		self.hello = []  # fields() -> a dict of fields the hello adds
		self.cancelled = []  # hook(unit) once a unit has been cancelled
		self.loaded = {}  # plugin name -> what its register returned

	def unit(self, kind, run, accepts=None):
		"""A unit leased by a message of this kind ({"type": kind, "id",
		"shard", "lease", ...}): run(unit, event, work) is the coroutine that
		does it, returning True when it ended normally, so the hub hears its
		stage is done. work holds "cancelled", "processes" (Agent.run_process)
		and "lease". accepts(event), if given, drops a malformed message."""
		self.units[kind] = (run, accepts)

	def message(self, kind, handler):
		"""handler(socket, event) for a JSON message of this kind, called as it is read."""
		self.messages[kind] = handler

	def file(self, kind, handler):
		"""async handler(socket, header, data) for a binary message (wire.pack) of this kind."""
		self.files[kind] = handler

	def hello_fields(self, fields):
		self.hello.append(fields)

	def on_cancel(self, hook):
		self.cancelled.append(hook)
