"""Reads the game's settings (game.toml), so nothing in the hive has a game's
name or paths written into it. The game is the folder that holds game.toml:
GAME_ROOT when set, otherwise the folder that contains framework/."""

import os
import re
import subprocess
import tomllib
from pathlib import Path

FRAMEWORK = Path(__file__).resolve().parents[1]
GAME_ROOT = Path(os.environ.get("GAME_ROOT") or FRAMEWORK.parent).resolve()
# Scripts this process starts (framework/scripts/*.sh) work on the same game.
os.environ["GAME_ROOT"] = str(GAME_ROOT)


def settings() -> dict:
	with open(GAME_ROOT / "game.toml", "rb") as file:
		return tomllib.load(file)


def setting(key: str, default=None):
	value = settings().get(key, default)
	if value is None:
		raise KeyError(f"game.toml has no setting '{key}' ({GAME_ROOT / 'game.toml'})")
	return value


# What a new game's game.toml says until framework/scripts/init-game.sh sets it.
PLACEHOLDER_REPOSITORY = "owner/my-game"


def repository() -> str:
	"""The game's GitHub repository, owner/name: game.toml's repository,
	unless it is missing or still the placeholder; then GITHUB_REPOSITORY
	(set on GitHub's machines), else the checkout's origin remote.
	framework/scripts/lib/hive.sh game_repository does the same for bash."""
	value = str(settings().get("repository") or "").strip()
	if value and value != PLACEHOLDER_REPOSITORY:
		return value
	if os.environ.get("GITHUB_REPOSITORY"):
		return os.environ["GITHUB_REPOSITORY"]
	try:
		url = subprocess.run(["git", "-C", str(GAME_ROOT), "remote", "get-url", "origin"],
			capture_output=True, text=True, timeout=10).stdout.strip()
	except (OSError, subprocess.SubprocessError):
		url = ""
	# https://github.com/owner/name(.git) or git@github.com:owner/name(.git)
	found = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?/?$", url)
	if found:
		return found.group(1)
	raise KeyError(f"no repository: set game.toml's repository ({GAME_ROOT / 'game.toml'}) or give the checkout an origin remote")


def cache_dir() -> Path:
	return Path.home() / ".cache" / setting("name")


def config_dir() -> Path:
	return Path.home() / ".config" / setting("name")
