"""The pipeline's cases for the hive's test runner, which finds this module
because game.toml's hive_plugins names the pipeline:

  GAME_ROOT=<game folder> nice -n 19 python3 framework/hive/hub/test_queue.py [-v]

test_build.py (the pull queue with build tasks, a-o), test_swap.py (the bake
swap and early publish, p-v), test_update.py (hot updates and engine
checks, w-zb) and test_uploads.py (a hub with uploads off)."""


def cases(harness):
	"""The cases, given the harness (framework/hive/hub/test_queue.py)."""
	from pipeline import test_build, test_swap, test_update, test_uploads
	q = test_build.bind(harness)
	return test_build.CASES + test_swap.cases(q) + test_update.cases(q) + test_uploads.cases(q)
