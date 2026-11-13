"""The pipeline on a build machine: one PipelineAgent per Agent, registered on
it (register_agent) through agent/plugins.py. It runs build units and engine
checks, renders previews and shares bakes, and is machine 1's uploader; its
parts are in the mixins below. The agent's second argument (Agent.target) is
the layout the machine builds."""
import os
import shutil

from pipeline.agent_build import BuildUnits
from pipeline.agent_engine import EngineUnits
from pipeline.agent_previews import Previews
from pipeline.agent_uploads import Uploads


class PipelineAgent(BuildUnits, Previews, Uploads, EngineUnits):
	def __init__(self, agent):
		self.agent = agent
		self.built = {}  # unit -> results folder
		self.by_branch = {}  # task id -> whether its objects went to a branch
		self.claims = {}  # claim number -> future for the job the coordinator gives it
		self.claim_number = 0
		self.timings = {}  # (task id, model) -> seconds per stage, reported when the model is done
		self.bakes_ready = {}  # (task id, model) -> future for the commits of every machine's bakes, set when the swap is over
		self.uploader = None
		self.start_width = self.start_known = None  # the width the hub says to start uploads at
		self.inbox = os.path.join(os.getcwd(), "upload-inbox")

	def hello(self):
		return {"layout": self.agent.target, "cargo": shutil.which("cargo") is not None}

	def claimed(self, _socket, event):
		claim = self.claims.get(event["id"])
		if claim and not claim.done():
			claim.set_result(event["job"])

	def bakes_told(self, _socket, event):
		ready = self.bakes_ready.get((event["task"], event["name"]))
		if ready and not ready.done() and event.get("done", True):
			ready.set_result(event["commits"])

	def cancelled(self, unit):
		# A unit dealt again after a cancel is built again.
		self.built.pop(unit, None)


def register_agent(hive):
	pipe = PipelineAgent(hive.agent)
	hive.unit("task", pipe.run_build)
	hive.unit("engine", pipe.run_engine, accepts=pipe.engine_fits)
	hive.message("uploader", pipe.uploader_told)
	hive.message("fetch-objects", pipe.fetch_told)
	hive.message("claimed", pipe.claimed)
	hive.message("bakes-ready", pipe.bakes_told)
	hive.file("upload", pipe.upload_arrived)
	hive.hello_fields(pipe.hello)
	hive.on_cancel(pipe.cancelled)
	return pipe
