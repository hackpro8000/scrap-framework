"""Pushes from a build machine through GitHub (scripts/push-folder.sh): its
baked paint layers for the other machines, and a finished preview's files."""
import os
import shutil
import subprocess
import tempfile

from agent.common import ROOT, SCRIPTS, say

LOG_LINES_KEPT = 200


def remote_head(branch):
	"""The commit a branch on GitHub points at, or ""."""
	listed = subprocess.run(["git", "ls-remote", "origin", f"refs/heads/{branch}"], capture_output=True, text=True, timeout=60)
	return listed.stdout.split("\t")[0].strip() if listed.returncode == 0 else ""


def trim_log(path):
	"""A render's log runs to hundreds of KB; its end says what went wrong."""
	try:
		with open(path, errors="replace") as file:
			lines = file.readlines()
	except OSError:
		return
	if len(lines) > LOG_LINES_KEPT:
		with open(path, "w") as file:
			file.writelines(lines[-LOG_LINES_KEPT:])


def push_bakes(model, share, out, since):
	"""Pushes the paint layers saved since `since`; returns the commit, or ""."""
	cache = os.path.join(ROOT, "art", "models", model, ".cache")
	fresh = tempfile.mkdtemp(dir=out)
	try:
		for entry in os.scandir(cache) if os.path.isdir(cache) else []:
			if entry.stat().st_mtime >= since:
				os.link(entry.path, os.path.join(fresh, entry.name))
		if not os.listdir(fresh):
			return ""
		branch = "build-bakes/" + share.replace("@", "-")
		pushed = subprocess.run([os.path.join(SCRIPTS, "push-folder.sh"), fresh, branch, f"bakes {share}"], capture_output=True, text=True)
		if pushed.returncode != 0 and "cannot lock ref" in pushed.stderr and "reference already exists" in pushed.stderr:
			# Another machine saved the same bake first: theirs serves as ours.
			say(f"bakes of {share} already saved by another machine; taking theirs")
			return remote_head(branch)
		if pushed.returncode != 0:
			say(f"could not push bakes of {share}: {pushed.stderr.strip()[-200:]}")
			return ""
		return pushed.stdout.strip()
	finally:
		shutil.rmtree(fresh, ignore_errors=True)


def push_preview(folder, share):
	"""The commit holding a finished preview's files, or "" if the push failed."""
	branch = "preview-results/" + share.replace("@", "-")
	pushed = subprocess.run([os.path.join(SCRIPTS, "push-folder.sh"), folder, branch, f"preview {share}"], capture_output=True, text=True)
	if pushed.returncode != 0:
		say(f"could not push preview {share}: {pushed.stderr.strip()[-200:]}")
		return ""
	return pushed.stdout.strip()
