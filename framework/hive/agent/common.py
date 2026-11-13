"""The standby agent's settings and its log lines (say, alert), which also
go to the coordinator through `forward` once connected (agent.session)."""
import os
import sys
import time

from game_settings import FRAMEWORK, GAME_ROOT, setting

# Game files and the git checkout are under ROOT, the game's folder (on a
# machine, the checkout); the framework's scripts are under SCRIPTS.
ROOT = str(GAME_ROOT)
SCRIPTS = os.path.join(FRAMEWORK, "scripts")
# The hub's wire format (wire.py) is shared with the agent.
sys.path.insert(0, os.path.join(FRAMEWORK, "hive", "hub"))

MAX_MESSAGE = 64 * 1024 * 1024
LOST_MINUTES = 3
ADDRESS_BRANCH = "build-results/coordinator-address"
HEARTBEAT_SECONDS = 10
REQUIRED_TOOLS = ("rg", "sd", "jq")
# Must equal the hub's (framework/hive/hub/oidc.py).
AUDIENCE = f"{setting('name')}-coordinator"
# A file bigger than this goes in parts, so heartbeats get onto the wire
# between them instead of waiting behind the whole file (send_file).
PART_BYTES = 1024 * 1024
# Failed connections in a row before ALERT TUNNEL_DOWN.
TUNNEL_ALERT_FAILURES = 3


# Lines also go to the coordinator, live, once connected (Agent.session).
forward = None


def say(message):
	# Wall-clock time to the millisecond, so a build's steps can be lined up
	# across machines (GitHub's runners keep their clocks synced).
	now = time.time()
	message = f"{time.strftime('%H:%M:%S', time.gmtime(now))}.{int(now % 1 * 1000):03d} {message}"
	print(f"agent: {message}", file=sys.stderr, flush=True)
	if forward:
		forward(message)


def alert(line):
	"""An ALERT or CLEARED line (docs/plans/multi-machine.md, Alerts): alone
	on its line in the job log, and passed to the hub when connected."""
	print(line, file=sys.stderr, flush=True)
	if forward:
		forward(line)
