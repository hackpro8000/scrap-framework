"""client.py's side of the hive's plugins (framework/hive/hive_plugins.py
loads them): the `hive` a plugin's register(hive) is given in client.py.
Through it a plugin adds commands of its own and the options they read."""


class ClientPlugins:
	side = "client"

	def __init__(self):
		self.commands = {}  # name -> run(url, arguments, parser), returning the exit code
		self.options = []  # add(parser): the options its commands read
		self.loaded = {}  # plugin name -> what its register returned

	def command(self, name, run):
		"""`client.py <name>`: run(url, arguments, parser) once the hub's control
		address is known; parser.error for bad arguments; returns the exit code."""
		self.commands[name] = run

	def option(self, add):
		self.options.append(add)
