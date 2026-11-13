"""The model pipeline's hive plugin: everything model-shaped the hive does.

The hive (framework/hive/hub, framework/hive/agent) knows only machines,
units and leases; this package makes a model build out of them. On the hub
(hub_plugin.py): build tasks cut into shards and preview shares, uploads to
Roblox, bake claims and the bake swap between machines, previews published
beside their models, the git link, and engine checks. In client.py
(client_plugin.py): `build` and `engine`. On a build machine
(agent_plugin.py): running a shard (scripts/standby-task.sh), its previews
and bake sharing, machine 1's uploads, and the engine compile.

It loads when game.toml's hive_plugins names it (the default). It imports the
hive's modules; they never import it."""


def register(hive):
	"""Adds the pipeline to a hub, client or agent (hive.side); returns its part there."""
	if hive.side == "hub":
		from pipeline.hub_plugin import register_hub
		return register_hub(hive)
	if hive.side == "client":
		from pipeline.client_plugin import register_client
		return register_client(hive)
	if hive.side == "agent":
		from pipeline.agent_plugin import register_agent
		return register_agent(hive)
	return None
