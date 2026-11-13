"""Loads the hive's plugins, so the hive itself knows nothing of the work its
machines do. Which plugins load comes from game.toml's hive_plugins: a
space-separated list of names, DEFAULT when the key is absent, none when it
is empty. Each name is a package framework/hive/<name>/ with a function
register(hive), called once for every hub, client or agent that starts.
hive.side ("hub", "client" or "agent") says which, and hive's methods are
where the plugin adds what it does (hub/hub_plugins.py,
hub/client_plugins.py, agent/plugins.py)."""
import importlib
import os
import re
import sys

from game_settings import FRAMEWORK, setting

HIVE = os.path.join(str(FRAMEWORK), "hive")
DEFAULT = "pipeline"
NAME = re.compile(r"[a-z][a-z0-9_]*")
# The hive's own packages, which no plugin may be named after.
TAKEN = {"hub", "agent"}


def names():
	"""The plugins game.toml asks for, in order."""
	return str(setting("hive_plugins", DEFAULT)).split()


def load(hive, wanted=None):
	"""Calls register(hive) of each plugin (game.toml's, or the names in
	`wanted`); returns {name: what its register returned}."""
	if HIVE not in sys.path:
		sys.path.insert(0, HIVE)
	loaded = {}
	for name in names() if wanted is None else wanted:
		if not NAME.fullmatch(name) or name in TAKEN or not os.path.isfile(os.path.join(HIVE, name, "__init__.py")):
			raise SystemExit(f"hive plugin {name!r} (game.toml hive_plugins) is not a package in {HIVE}")
		loaded[name] = importlib.import_module(name).register(hive)
	return loaded
