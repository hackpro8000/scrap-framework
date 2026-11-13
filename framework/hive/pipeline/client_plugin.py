"""The pipeline's commands in client.py (registered by register_client):

  client.py build <commit> [--no-upload] [--wait S] [--preview A,B] [--preview-only] [--units N]
                                    # a model build (client_build.py; default wait 600 s)
  client.py engine <full sha> [--wait S]
                                    # compile the engine on one machine with cargo;
                                    # exits 1 on a failed compile (default wait 900 s)"""
import asyncio
import sys

from client_connection import alert
from hub_update import SHA
from pipeline.client_build import build, resolve_ref
from pipeline.client_engine import engine


def add_options(parser):
	parser.add_argument("--no-upload", action="store_true")
	parser.add_argument("--no-seat", action="store_true", help="build: accepted and ignored; there are no seats any more")
	parser.add_argument("--units", type=int, default=0, help="build: cut the task into this many units (default: one per machine connected)")
	parser.add_argument("--preview", default="", help="models to render, comma-separated")
	parser.add_argument("--preview-only", action="store_true", help="render the previews without building the layout")


def run_build(url, arguments, parser):
	if not arguments.ref:
		parser.error("build needs a commit")
	ref, why = resolve_ref(arguments.ref)
	if not ref:
		alert(f"ALERT BAD_REF: {arguments.ref} is not a commit the machines can fetch from GitHub ({why}) "
			"| push it first (scripts/push-wip.sh for unfinished work) and post again")
		sys.exit(1)
	previews = [name for name in arguments.preview.split(",") if name]
	if arguments.no_seat:
		print("--no-seat: nothing to do; every connected machine takes units from the queue", file=sys.stderr)
	return asyncio.run(build(url, ref, not arguments.no_upload, arguments.wait or 600, previews, not arguments.preview_only,
		arguments.units or None))


def run_engine(url, arguments, parser):
	if not SHA.fullmatch(arguments.ref or ""):
		parser.error("engine needs a full 40-character commit sha")
	return asyncio.run(engine(url, arguments.ref, arguments.wait or 900))


def register_client(hive):
	hive.option(add_options)
	hive.command("build", run_build)
	hive.command("engine", run_engine)
	return None
