"""The pipeline's cases for the hive's test runner, which finds this module
because game.toml's hive_plugins names the pipeline:

  GAME_ROOT=proof/scrap-heist nice -n 19 python3 framework/hive/hub/test_queue.py [-v]

test_build.py (the pull queue with build tasks, a-o), test_swap.py (the bake
swap and early publish, p-v) and test_update.py (hot updates and engine
checks, w-zb)."""


def cases(harness):
	"""The cases, given the harness (framework/hive/hub/test_queue.py)."""
	from pipeline import test_build, test_swap, test_update
	q = test_build.bind(harness)
	return test_build.CASES + test_swap.cases(q) + test_update.cases(q)
