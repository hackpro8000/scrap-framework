"""A case for a hub with uploads off (hub_plugin.py, refusal): no Roblox key
and no ROBLOX_CREATOR_ID, as in a new game's repository with no secrets. Run
by the hive's test runner through tests.py with the other pipeline cases."""
import json
import os

import websockets

from pipeline import uploader as uploading


def cases(q):
	"""The case, given test_build's module (its Hub pieces, Fake, post, check)."""

	async def case_uploads_off():
		# The environment, the key file and the creator id read at import, all cleared for the case.
		saved = {name: os.environ.pop(name, None) for name in ("ROBLOX_API_KEY", "ROBLOX_CREATOR_ID")}
		key_file, creator = uploading.KEY_FILE, uploading.CREATOR_ID
		uploading.KEY_FILE, uploading.CREATOR_ID = os.path.join(os.sep, "nonexistent", "roblox-api-key"), ""
		at, fakes = None, []
		try:
			at = await q.h.Hub(settings={"layout": "TestMap"}, fake=q.Fake).start()
			pipe = q.pipe(at)
			q.check("Roblox API key" in pipe.uploads_off and "ROBLOX_CREATOR_ID" in pipe.uploads_off, f"uploads off: {pipe.uploads_off!r}")
			q.check(" (uploads off)" in at.c.plugins.notes, f"notes: {at.c.plugins.notes}")
			fakes = await at.machines(["g1", "g2"])
			await q.until(lambda: len(at.c.connected()) == 2)
			watch = await q.post(at)
			await watch.finished()
			await watch.close()
			problem = q.each_once(fakes, watch.task, 2)
			q.check(not problem, problem)
			socket = await websockets.connect(at.control_url)
			await socket.send(json.dumps({"type": "build", "ref": "abc1234", "upload": True, "previews": [], "build": True}))
			answer = json.loads(await socket.recv())
			await socket.close()
			text = answer.get("text", "")
			q.check(answer.get("type") == "error" and text.startswith("uploads are off") and "--no-upload" in text, f"answered {answer}")
			q.check(not at.c.tasks, f"the refused build was posted: {list(at.c.tasks)}")
			return f"no key, no creator: hub up, a --no-upload build dealt to g1+g2 and finished; an upload refused: {text[:70]}..."
		finally:
			uploading.KEY_FILE, uploading.CREATOR_ID = key_file, creator
			for name, value in saved.items():
				if value is not None:
					os.environ[name] = value
			if at:
				await at.stop(fakes)

	return [("uploads-off", case_uploads_off)]
