"""A session reached through git (--git-link, a part of PipelineHub): the
hub runs on build machine 1 for a session that can't connect out
(scripts/standby-start.sh --on-machine). It takes build tasks from the
build-queue branch (scripts/send-build.sh posts them there; the one link
that still polls) and pushes each finished task's results, objects left
out, as one commit to build-results/coordinator."""
import asyncio
import os
import subprocess
import tempfile
import time

from hub_config import ROOT, say

LINK_RESULTS = "build-results/coordinator"
LINK_INTERVAL = 3


class GitLink:
	def git(self, *arguments, **options):
		return subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True, **options)

	async def link(self):
		"""Takes tasks posted to build-queue since this hub started."""
		since, seen, taken = int(time.time()), "", set()
		while True:
			head = (await asyncio.to_thread(self.git, "ls-remote", "origin", "refs/heads/build-queue")).stdout.split("\t")[0]
			if head and head != seen and self.hub.roster:
				fetched = await asyncio.to_thread(self.git, "fetch", "-q", "--depth=1", "origin", head)
				if fetched.returncode == 0:
					seen = head
					files = (await asyncio.to_thread(self.git, "ls-tree", "--full-tree", "--name-only", head, "tasks/")).stdout.split()
					for name in sorted(files):
						identity = os.path.basename(name)[:-4]
						posted = identity[1:].split("-")[0]
						if identity in taken or not posted.isdigit() or int(posted) < since:
							continue
						taken.add(identity)
						text = (await asyncio.to_thread(self.git, "show", f"{head}:{name}")).stdout
						fields = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
						if "ref" in fields and "upload-of" not in fields:
							say(f"task {identity} from the build-queue branch")
							await self.post(identity, fields["ref"], fields.get("upload") != "no")
							await self.hub.deal()
			await asyncio.sleep(LINK_INTERVAL)

	def push_results(self, task):
		"""One commit on build-results/coordinator with the task's results,
		objects left out, through a temporary index."""
		index = tempfile.mktemp()
		environment = {**os.environ, "GIT_INDEX_FILE": index}
		for directory, _, names in os.walk(task.out):
			for name in names:
				if name.endswith(".glb"):
					continue
				path = os.path.join(directory, name)
				blob = self.git("hash-object", "-w", path).stdout.strip()
				relative = os.path.relpath(path, task.out)
				self.git("update-index", "--add", "--cacheinfo", f"100644,{blob},{relative}", env=environment)
		tree = self.git("write-tree", env=environment).stdout.strip()
		if os.path.exists(index):
			os.remove(index)
		parent = []
		if self.git("fetch", "-q", "--depth=1", "origin", f"refs/heads/{LINK_RESULTS}").returncode == 0:
			parent = ["-p", self.git("rev-parse", "FETCH_HEAD").stdout.strip()]
		commit = self.git("commit-tree", tree, *parent, "-m", f"task {task.id}").stdout.strip()
		pushed = self.git("push", "-q", "origin", f"{commit}:refs/heads/{LINK_RESULTS}")
		say(f"task {task.id}: results pushed" if pushed.returncode == 0 else f"task {task.id}: push failed {pushed.stderr}")
