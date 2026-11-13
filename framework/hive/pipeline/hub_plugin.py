"""The pipeline on the hub: one PipelineHub per hub, registered on it
(register_hub) through hub/hub_plugins.py. It holds the pipeline's settings
and its uploader, posts build tasks and engine checks, and takes the
model-shaped messages machines send; its parts are in the mixins below.

serve's options it adds: --layout L (default: game.toml's default_layout),
--dry-upload (nothing reaches Roblox), --uploads-on-machine (build machine 1
uploads with the repo's ROBLOX_API_KEY: what framework/scripts/coordinator.sh picks
when this session has no Roblox key), --no-uploads, and --git-link (a hub on
machine 1 for a session that can't connect out: tasks from the build-queue
branch, results pushed to build-results/coordinator, hub_link.py).

Uploads are optional. With --no-uploads, or with no Roblox key or no
ROBLOX_CREATOR_ID where the hub runs (and neither --dry-upload nor
--uploads-on-machine), they are off: the hub says so once, builds with
upload off and previews run as ever, and a build that would upload is
refused with the reason (refusal)."""
import json
import sys

from game_settings import setting
from hub_config import ROOT, say
from pipeline import uploader as uploading
from pipeline.build_task import BuildTask
from pipeline.hub_builds import Builds
from pipeline.hub_engine import EngineChecks, EngineTask
from pipeline.hub_link import GitLink
from pipeline.hub_previews import PreviewJobs
from pipeline.hub_uploads import Uploads
from pipeline.remote_uploader import RemoteUploader


class PipelineHub(Builds, Uploads, GitLink, PreviewJobs, EngineChecks):
	def __init__(self, hive):
		self.hive, self.hub = hive, hive.hub
		self.layout = setting("default_layout")
		self.dry = self.git_link = self.uploads_on_machine = False
		self.uploads_off = ""  # why uploads are off, in plain words; "" when they are on
		self.uploader = None  # set up from serve's options (setup)

	@staticmethod
	def add_options(parser):
		parser.add_argument("--layout", default=setting("default_layout"))
		parser.add_argument("--dry-upload", action="store_true")
		parser.add_argument("--git-link", action="store_true")
		parser.add_argument("--uploads-on-machine", action="store_true")
		parser.add_argument("--no-uploads", action="store_true")

	def setup(self, settings):
		"""serve's options (or a test's): the layout, how objects are uploaded,
		and the git link, which then runs beside the hub."""
		hub = self.hub
		self.layout = settings.get("layout") or setting("default_layout")
		self.dry = bool(settings.get("dry_upload"))
		self.git_link = bool(settings.get("git_link"))
		self.uploads_on_machine = bool(settings.get("uploads_on_machine"))
		if settings.get("no_uploads"):
			self.uploads_off = "the hub was started with --no-uploads"
		elif not (self.dry or self.uploads_on_machine):
			self.uploads_off = uploading.missing()
		# Nothing must reach Roblox from a hub that lets in any machine.
		if hub.test_without_identity and not (self.dry or self.uploads_on_machine or self.uploads_off):
			sys.exit("--test-without-identity is only for a local dry run (agent host 127.0.0.1, --dry-upload)")
		if hub.relay_results and self.git_link:
			sys.exit("--relay-results replaces --git-link; pick one")
		if self.uploads_on_machine:
			self.uploader = RemoteUploader(self.layout)
			self.uploader.sent_paths = {}
		else:
			# With uploads off it stays inert: a build that would upload is refused (refusal).
			dry = self.dry or bool(self.uploads_off)
			self.uploader = uploading.Uploader(ROOT, self.layout, say, dry=dry, on_done=self.local_answer)
		if self.uploads_off:
			say(f"uploads are off: {self.uploads_off}. Builds with --no-upload and previews work; {uploading.TURN_ON}")
		self.hive.notes += [" (dry upload)"] if self.dry else []
		self.hive.notes += [" (machine 1 uploads)"] if self.uploads_on_machine else []
		self.hive.notes += [" (uploads off)"] if self.uploads_off else []
		self.hive.state["dry_upload"] = self.dry
		self.hive.state["uploads_off"] = self.uploads_off
		return self.link() if self.git_link else None

	def refusal(self, upload, build=True):
		"""Why a task can't be taken: it would upload while uploads are off; else ""."""
		if not (self.uploads_off and upload and build):
			return ""
		return (f"uploads are off on this hub ({self.uploads_off}): build with --no-upload, or --preview-only "
			f"for previews alone; {uploading.TURN_ON}")

	# --- machines' messages about a unit they hold (hub_plugins.HubPlugins.message) ---

	async def on_claim(self, machine, socket, event, task, slot, lease):
		job = self.next_job(task, lease, event) if isinstance(task, BuildTask) else -1
		await socket.send(json.dumps({"type": "claimed", "id": event["id"], "job": job}))

	async def on_claim_refused(self, machine, socket, event):
		# A stopped unit's engine gets nothing more.
		await socket.send(json.dumps({"type": "claimed", "id": event.get("id"), "job": -1}))

	async def on_bakes_pushed(self, machine, socket, event, task, slot, lease):
		if isinstance(task, BuildTask):
			await self.bakes_pushed(task, event, lease, machine)

	async def on_preview_ready(self, machine, socket, event, task, slot, lease):
		if isinstance(task, BuildTask):
			await self.preview_ready(task, slot, event, lease)

	async def on_preview_pushed(self, machine, socket, event, task, slot, lease):
		if isinstance(task, BuildTask):
			await self.preview_pushed(task, slot, event, lease)

	async def on_previews_done(self, machine, socket, event, task, slot, lease):
		if isinstance(task, BuildTask):
			await self.previews_done(task, slot)

	async def on_engine(self, machine, socket, event, task, slot, lease):
		if isinstance(task, EngineTask):
			await self.engine_event(task, slot, event, machine.name)


def register_hub(hive):
	pipe = PipelineHub(hive)
	hive.option(pipe.add_options)
	hive.setup(pipe.setup)
	hive.request("build", pipe.build_request)
	hive.request("engine", pipe.engine_request)
	hive.loader(pipe.load_task)
	hive.on_join(pipe.machine_joined)
	hive.on_leave(pipe.machine_left)
	hive.message("uploaded", pipe.machine_uploaded, unit=False)
	hive.message("claim", pipe.on_claim, otherwise=pipe.on_claim_refused)
	hive.message("bakes-pushed", pipe.on_bakes_pushed)
	hive.message("preview-ready", pipe.on_preview_ready)
	hive.message("preview-pushed", pipe.on_preview_pushed)
	hive.message("previews-done", pipe.on_previews_done)
	hive.message("engine-output", pipe.on_engine)
	hive.message("engine-done", pipe.on_engine)
	return pipe
