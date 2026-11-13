"""Reads the game's settings (game.toml), so nothing in the hive has a game's
name or paths written into it. The game is the folder that holds game.toml:
GAME_ROOT when set, otherwise the folder that contains framework/."""

import os
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


def cache_dir() -> Path:
	return Path.home() / ".cache" / setting("name")


def config_dir() -> Path:
	return Path.home() / ".config" / setting("name")
