"""The coordinator's settings (paths, limits, lease times, name patterns)
and its log line, shared by every hub module (coordinator.py)."""
import ipaddress
import os
import re
import sys

# The game's settings (framework/hive/game_settings.py) sit one folder up.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from game_settings import FRAMEWORK, GAME_ROOT, cache_dir, setting  # noqa: E402

# Game files (art/, results, its git checkout) are under ROOT, the game's
# folder; the framework's own scripts are under SCRIPTS.
ROOT = str(GAME_ROOT)
SCRIPTS = os.path.join(FRAMEWORK, "scripts")
REPOSITORY = setting("repository")
DEFAULT_LAYOUT = setting("default_layout")
WORKFLOW = ".github/workflows/build-standby.yml"
MAX_MESSAGE = 64 * 1024 * 1024
# Control only ever receives small requests; the public port refuses big ones before admission.
MAX_CONTROL_MESSAGE = 64 * 1024
MAX_SIGNATURE = 4096
STATE = os.path.join(cache_dir(), "coordinator.json")
# Posted tasks not yet completed, reloaded when a coordinator restarts.
TASKS = os.path.join(os.path.dirname(STATE), "tasks.json")
# Finished tasks a reconnecting session can still ask for (watch-task).
KEEP_FINISHED = 20
WORKER_PREFIX = "worker:"
MAX_WORKERS = 100
LINK_RESULTS = "build-results/coordinator"
LINK_INTERVAL = 3
# --control-key: a control connection counts only once the session has
# signed a fresh nonce with its key (scripts/coordinator.sh key).
CONTROL_NAMESPACE = f"{setting('name')}-control"
CHALLENGE_SECONDS = 30
TAILNET = ipaddress.ip_network("100.64.0.0/10")
# What a machine may name: a model folder, and a task folder.
MODEL_NAME = re.compile(r"[A-Za-z0-9_]+")
TASK_NAME = re.compile(r"[A-Za-z0-9-]+")
COMMIT = re.compile(r"[0-9a-f]{7,64}")
# Most one shard may send for one task; further files are refused.
MAX_SHARD_FILES = 20_000
MAX_SHARD_BYTES = 8 * 1024 ** 3
RESULTS = os.path.join(ROOT, ".standby-results")
# When a leased unit goes back to the queue (Coordinator.lease_lost); each
# can be shortened through the environment or the constructor, for tests.
LEASE_GRACE_SECONDS = 30  # its machine's connection closed this long
LEASE_SILENT_SECONDS = 120  # nothing heard from its machine this long
LEASE_WEDGED_SECONDS = 300  # its log, files and claims all quiet this long
# A machine gone this long holding nothing leaves the roster.
GONE_FORGOTTEN_SECONDS = 600


def say(message):
	print(f"coordinator: {message}", file=sys.stderr, flush=True)
