#!/usr/bin/env python3
"""Talks to the running hub (coordinator.py) from this session.

  framework/hive/hub/client.py status          # the run, the roster by name, queued units per task
  framework/hive/hub/client.py machines        # what each machine is doing now
  framework/hive/hub/client.py stop-machines   # standby machines end now
  framework/hive/hub/client.py clear-tasks     # drop open tasks (after ALERT STRANDED_TASK)
  framework/hive/hub/client.py mint-workers <count>
  framework/hive/hub/client.py open-workers    # no longer needed: says so and does nothing
  framework/hive/hub/client.py numbered        # the numbers of the numbered machines connected, one line
  framework/hive/hub/client.py machine-tokens <first> <last>  # no hub needed
                                              # tokens for a new pool of workers
                                              # (framework/scripts/cloud-worker.sh), one
                                              # line each: m<n> <token>
  framework/hive/hub/client.py wait-machines [N] [--wait S]
                                              # returns once N machines are up
                                              # (default: all of the run)
  framework/hive/hub/client.py update <full sha> [--force] [--wait S]
                                              # hot update: the hub and every machine
                                              # move to that commit (default wait 180 s)
  framework/hive/hub/client.py <command of a plugin> ...
                                              # the commands game.toml's hive_plugins
                                              # add (each plugin's client modules say what they do)

`status` prints abnormalities as one line each, starting ALERT <KIND>:
(CLEARED <KIND> when one resolves); the kinds are listed in
docs/plans/multi-machine.md, Alerts. Exits 2 when no hub is running.
"""
import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# The modules below hold the code; the names client.py had are still importable from it.
import wire  # noqa: E402,F401
from client_connection import (ROOT, STATE, CONTROL_KEY, CONTROL_NAMESPACE, MAX_MESSAGE, RECONNECT_SECONDS,  # noqa: E402,F401
	MAX_RECONNECTS, RECONNECT_BUDGET_SECONDS, control_url, Control, sign, connect, alert, http_status, control, watch_again)
from client_commands import (STRANDED_AGE_SECONDS, SHORT_SECONDS, LIFETIME_WARN_SECONDS, status, roster_state,  # noqa: E402,F401
	status_alerts, lifetime_alert, clear_tasks, mint_workers, wait_machines, numbered, open_workers, machine_tokens,
	stop_machines, machines)
from client_update import SHA, update  # noqa: E402
from client_plugins import ClientPlugins  # noqa: E402
import hive_plugins  # noqa: E402

OWN_COMMANDS = ["status", "machines", "stop-machines", "wait-machines", "mint-workers", "open-workers", "machine-tokens",
	"numbered", "clear-tasks", "update"]


def main():
	hive = ClientPlugins()
	hive.loaded = hive_plugins.load(hive)
	parser = argparse.ArgumentParser()
	parser.add_argument("command", choices=OWN_COMMANDS + [name for name in hive.commands if name not in OWN_COMMANDS])
	parser.add_argument("ref", nargs="?")
	parser.add_argument("last", nargs="?")
	parser.add_argument("--wait", type=int, default=None, help="seconds (wait-machines 600; update 180; a plugin's command its own)")
	parser.add_argument("--force", action="store_true", help="update: even with tasks open")
	for add in hive.options:
		add(parser)
	arguments = parser.parse_args()
	if arguments.command == "machine-tokens":
		if not (arguments.ref or "").isdigit() or not (arguments.last or arguments.ref).isdigit():
			parser.error("machine-tokens needs a first and last machine number")
		sys.exit(machine_tokens(int(arguments.ref), int(arguments.last or arguments.ref)))
	url = control_url()
	if not url:
		print("no coordinator running (framework/scripts/coordinator.sh start)", file=sys.stderr)
		sys.exit(2)
	if arguments.command == "status":
		code = asyncio.run(status(url))
	elif arguments.command == "machines":
		code = asyncio.run(machines(url))
	elif arguments.command == "wait-machines":
		code = asyncio.run(wait_machines(url, int(arguments.ref or 0), arguments.wait or 600))
	elif arguments.command == "update":
		if not SHA.fullmatch(arguments.ref or ""):
			parser.error("update needs a full 40-character commit sha")
		code = asyncio.run(update(url, arguments.ref, arguments.force, arguments.wait or 180))
	elif arguments.command == "stop-machines":
		code = asyncio.run(stop_machines(url))
	elif arguments.command == "clear-tasks":
		code = asyncio.run(clear_tasks(url))
	elif arguments.command == "open-workers":
		code = open_workers()
	elif arguments.command == "numbered":
		code = asyncio.run(numbered(url))
	elif arguments.command == "mint-workers":
		if not (arguments.ref or "").isdigit():
			parser.error("mint-workers needs a count")
		code = asyncio.run(mint_workers(url, int(arguments.ref)))
	else:
		code = hive.commands[arguments.command](url, arguments, parser)
	sys.exit(code)


if __name__ == "__main__":
	main()
