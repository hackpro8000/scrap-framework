#!/usr/bin/env bash
# Starts, stops or reports the build coordinator (framework/hive/hub/) in
# this session, with an address the standby machines can reach.
#
#   framework/scripts/coordinator.sh start [tailscale|cloudflare|auto] [--dry-upload]
#   framework/scripts/coordinator.sh url        # the address to give standby machines
#   framework/scripts/coordinator.sh status
#   framework/scripts/coordinator.sh machines   # what each machine is doing right now
#   framework/scripts/coordinator.sh stop
#   framework/scripts/coordinator.sh attach [run id]   # use machine 1's coordinator
#   framework/scripts/coordinator.sh key        # prints this session's control key
#   framework/scripts/coordinator.sh worker-key # makes the numbered machines' key and stores it as a repo secret
#
# attach points this session at the coordinator build machine 1 runs for
# that standby run (the newest when no id is given): over the tailnet when
# the repository has the TS_AUTHKEY secret, else through the Cloudflare
# tunnel whose address machine 1 publishes (address.json on
# build-results/coordinator-address), waited for up to ATTACH_WAIT_SECONDS
# (300). It says "attached" only once the control port answers, and
# otherwise names what it waited for. stop then ends its machines but kills
# nothing here. key makes, once, the key pair whose signature machine 1's
# control port asks for; only the public half leaves here.
#
# Routes: tailscale puts the machine port on this session's tailnet address
# (the machines join the tailnet with the repo's TS_AUTHKEY secret);
# cloudflare keeps it on localhost and opens a Cloudflare quick tunnel to it,
# an https address made by an outbound connection only. auto takes tailscale
# when this session is on a tailnet and the repo has TS_AUTHKEY, else
# cloudflare. Either way a machine is let in only with GitHub's identity
# token for this repo's standby workflow (framework/hive/hub/oidc.py).
#
# Uploads run here when this session has the Roblox key (ROBLOX_API_KEY, or
# roblox-api-key in the game's config folder) and ROBLOX_CREATOR_ID; without
# them, build machine 1 does them with the repo's ROBLOX_API_KEY and
# ROBLOX_CREATOR_ID secrets, still over the live connections; with neither,
# uploads are off (builds with --no-upload and previews still work). If this
# session can't connect out at all, start standby with
# framework/scripts/standby-start.sh --on-machine.

set -euo pipefail

source "$(dirname "$0")/lib/game.sh"
source "$(dirname "$0")/lib/hive.sh"
hub="${FRAMEWORK}/hive/hub"
logs="$(game_cache_dir)"
state="${logs}/coordinator.json"
agent_port=8765
# How long attach waits in all for machine 1's address and its answer.
attach_seconds="${ATTACH_WAIT_SECONDS:-300}"
mkdir -p "${logs}"

json() {
	python3 -c "import json,sys; print(json.load(open('${state}')).get('$1', ''))" 2> /dev/null || true
}

remote() {
	[ -f "${state}" ] && [ "$(json remote)" = True ]
}

running() {
	remote || { [ -f "${state}" ] && kill -0 "$(json pid)" 2> /dev/null; }
}

# Whether the repository has the TS_AUTHKEY secret: yes, no, or unknown
# (its secrets can't be listed from here).
tailnet_secret() {
	local secrets
	secrets="$(gh secret list -R "$(game_repository)" 2> /dev/null)" || { echo unknown; return 0; }
	if grep -q "^TS_AUTHKEY" <<< "${secrets}"; then echo yes; else echo no; fi
}

# The tunnel address machine 1 of run $1 published (address.json, one line
# of JSON), or nothing while it hasn't.
published_address() {
	gh api -H "Accept: application/vnd.github.raw" \
		"repos/$(game_repository)/contents/address.json?ref=build-results/coordinator-address" 2> /dev/null |
		jq -c --arg run "$1" 'select(.run == $run and .control != null and .agent != null)' 2> /dev/null || true
}

# How machine 1's job of run $1 ended (its conclusion), or nothing while it runs.
machine_one_ended() {
	gh api "repos/$(game_repository)/actions/runs/$1/jobs" \
		--jq '.jobs[] | select(.name | test("\\(1\\)$")) | select(.status == "completed") | .conclusion' 2> /dev/null || true
}

attach() {
	local run="${1:-}" address="" route=cloudflare deadline ended answer control
	# Attaching again replaces a machine-1 hub's record (that hub may have
	# ended, or this is a newer run); only a hub running on this computer
	# has to be stopped first.
	if running && ! remote; then
		echo "a coordinator is already running here; framework/scripts/coordinator.sh stop it first" >&2
		return 1
	fi
	[ -n "${run}" ] || run="$(gh run list -R "$(game_repository)" --workflow build-standby.yml --limit 1 \
		--json databaseId --jq '.[0].databaseId // empty' 2> /dev/null || true)"
	[ -n "${run}" ] || { echo "no standby run found in $(game_repository); give its id: framework/scripts/coordinator.sh attach <run id>" >&2; return 1; }
	deadline=$((SECONDS + attach_seconds))
	address="$(published_address "${run}")"
	# No tunnel address: over the tailnet when the repository has TS_AUTHKEY
	# (machine 1 then publishes none), else it is still to come.
	if [ -z "${address}" ]; then
		case "$(tailnet_secret)" in
			yes) route=tailscale ;;
			unknown) if tailscale ip -4 > /dev/null 2>&1; then route=tailscale; fi ;;
		esac
	fi
	if [ -z "${address}" ] && [ "${route}" = cloudflare ]; then
		echo "waiting up to ${attach_seconds}s for machine 1 of run ${run} to publish its tunnel address (address.json on build-results/coordinator-address)" >&2
		while [ -z "${address}" ]; do
			ended="$(machine_one_ended "${run}")"
			if [ -n "${ended}" ]; then
				echo "machine 1's job of run ${run} ended (${ended}) before it published a tunnel address; see: gh run view ${run} --log-failed" >&2
				return 1
			fi
			if [ "${SECONDS}" -ge "${deadline}" ]; then
				echo "machine 1 of run ${run} published no tunnel address in ${attach_seconds}s (waited for address.json naming run ${run} on build-results/coordinator-address)" >&2
				return 1
			fi
			sleep 5
			address="$(published_address "${run}")"
		done
	fi
	python3 - "${state}" "${run}" "${address}" "$(game_setting host_prefix)" << 'PY'
import json, sys
path, run, address, host_prefix = sys.argv[1:]
if address:
	address = json.loads(address)
	state = {"remote": True, "control": address["control"], "agent_url": address["agent"], "route": "machine-1 over cloudflare", "run": run}
else:
	state = {"remote": True, "control": f"ws://{host_prefix}-coordinator-{run}:8766", "agent_url": "machine-1", "route": "machine-1 over tailscale", "run": run}
json.dump(state, open(path, "w"))
PY
	# Attached only once machine 1's control port answers this session's key.
	control="$(json control)"
	if ! answer="$(python3 "${hub}/client.py" status 2>&1)"; then
		echo "waiting up to $((deadline - SECONDS > 0 ? deadline - SECONDS : 0))s for machine 1's control port ${control} to answer" >&2
		until answer="$(python3 "${hub}/client.py" status 2>&1)"; do
			if [ "${SECONDS}" -ge "${deadline}" ]; then
				rm -f "${state}"
				echo "machine 1's control port ${control} of run ${run} did not answer in ${attach_seconds}s ($(tail -n 1 <<< "${answer}")); not attached" >&2
				return 1
			fi
			sleep 5
		done
	fi
	echo "attached to machine 1's coordinator of run ${run} ($(json route)): $(head -n 1 <<< "${answer}")" >&2
}

key() {
	local key="${logs}/control-key"
	if [ ! -f "${key}" ]; then
		ssh-keygen -q -t ed25519 -N "" -C "$(game_setting name)-control" -f "${key}" < /dev/null
		echo "made ${key}; it never leaves this computer" >&2
	fi
	cat "${key}.pub"
}

# The key the numbered cloud machines' tokens are made from: kept on this
# computer and as the repo's WORKER_KEY secret, which machine 1 gives its
# coordinator. Making a new one would cut off every machine that joined.
worker_key() {
	local key="${logs}/worker-key"
	if [ ! -f "${key}" ]; then
		(umask 077; python3 -c 'import secrets; print(secrets.token_hex(32))' > "${key}")
		echo "made ${key}" >&2
	fi
	gh secret set WORKER_KEY < "${key}" > /dev/null && echo "the repo's WORKER_KEY secret holds this computer's worker key" >&2
}

set_url() {
	python3 - "${state}" "$1" "$2" << 'PY'
import json, sys
path, url, route = sys.argv[1:]
state = json.load(open(path))
state["agent_url"], state["route"] = url, route
json.dump(state, open(path, "w"))
PY
}

route_for() {
	local wanted="$1"
	if [ "${wanted}" != "auto" ]; then
		echo "${wanted}"
	elif tailscale ip -4 > /dev/null 2>&1 && [ "$(tailnet_secret)" = yes ]; then
		echo tailscale
	elif command -v cloudflared > /dev/null; then
		echo cloudflare
	else
		echo none
	fi
}

# The hub's upload option: none (uploads here), --uploads-on-machine or
# --no-uploads; why goes to stderr.
upload_option() {
	local secrets
	if [ -n "${ROBLOX_CREATOR_ID:-}" ] && { [ -n "${ROBLOX_API_KEY:-}" ] || [ -f "$(game_config_dir)/roblox-api-key" ]; }; then
		return 0
	fi
	if ! secrets="$(gh secret list -R "$(game_repository)" 2> /dev/null)"; then
		echo "no Roblox key or ROBLOX_CREATOR_ID in this session, and the repository's secrets can't be listed: build machine 1 will upload, if it has them" >&2
		echo "--uploads-on-machine"
	elif grep -q "^ROBLOX_API_KEY" <<< "${secrets}" && grep -q "^ROBLOX_CREATOR_ID" <<< "${secrets}"; then
		echo "no Roblox key or ROBLOX_CREATOR_ID in this session: build machine 1 will upload with the repo's secrets" >&2
		echo "--uploads-on-machine"
	else
		echo "uploads are off: neither this session nor the repository has ROBLOX_API_KEY and ROBLOX_CREATOR_ID; builds with --no-upload and previews work" >&2
		echo "--no-uploads"
	fi
}

start() {
	local route dry="" host="127.0.0.1" url
	route="$(route_for "${1:-auto}")"
	[ "${2:-}" = "--dry-upload" ] && dry="--dry-upload"
	[ -n "${dry}" ] || dry="$(upload_option)"
	if running; then
		echo "coordinator already running: $(json agent_url)" >&2
		return 0
	fi
	case "${route}" in
		tailscale) host="$(tailscale ip -4 | head -n 1)" ;;
		cloudflare) ;;
		*) echo "no route out of this session: start standby without a coordinator" >&2; return 1 ;;
	esac
	cd "${GAME_ROOT}"
	nohup setsid python3 "${hub}/coordinator.py" serve --agent-host "${host}" --agent-port "${agent_port}" ${dry} \
		> "${logs}/coordinator.log" 2>&1 < /dev/null &
	for _ in $(seq 1 50); do
		grep -q "machines on" "${logs}/coordinator.log" 2> /dev/null && break
		sleep 0.2
	done
	running || { echo "coordinator did not start:" >&2; tail -n 20 "${logs}/coordinator.log" >&2; return 1; }
	if [ "${route}" = tailscale ]; then
		url="ws://${host}:${agent_port}"
	else
		nohup setsid cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${agent_port}" \
			> "${logs}/tunnel.log" 2>&1 < /dev/null &
		echo $! > "${logs}/tunnel.pid"
		url=""
		for _ in $(seq 1 100); do
			url="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "${logs}/tunnel.log" | head -n 1 || true)"
			[ -n "${url}" ] && break
			sleep 0.3
		done
		[ -n "${url}" ] || { echo "the Cloudflare tunnel did not come up:" >&2; tail -n 20 "${logs}/tunnel.log" >&2; stop; return 1; }
		url="wss://${url#https://}"
	fi
	set_url "${url}" "${route}"
	echo "coordinator up over ${route}: ${url}" >&2
}

stop() {
	# Machines first: left running they'd hold all the account's machine
	# slots, and a new standby run would wait in GitHub's queue behind them.
	if running; then
		python3 "${hub}/client.py" stop-machines > /dev/null 2>&1 && echo "told the machines to stop" >&2 || true
	fi
	# Machine 1 runs a remote coordinator: nothing here to kill.
	if remote; then
		rm -f "${state}"
		echo "detached from machine 1's coordinator" >&2
		return 0
	fi
	if [ -f "${logs}/tunnel.pid" ]; then
		kill "$(cat "${logs}/tunnel.pid")" 2> /dev/null || true
		rm -f "${logs}/tunnel.pid"
	fi
	if running; then
		kill "$(json pid)" 2> /dev/null || true
	fi
	rm -f "${state}"
	echo "coordinator stopped" >&2
}

case "${1:-status}" in
	start) start "${2:-auto}" "${3:-}" ;;
	stop) stop ;;
	attach) attach "${2:-}" ;;
	key) key ;;
	worker-key) worker_key ;;
	url) running && json agent_url ;;
	status)
		if running; then
			echo "coordinator up over $(json route): $(json agent_url)"
			python3 "${hub}/client.py" status || true
		else
			echo "no coordinator running"
		fi
		;;
	machines) python3 "${hub}/client.py" machines ;;
	*) awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 1 ;;
esac
