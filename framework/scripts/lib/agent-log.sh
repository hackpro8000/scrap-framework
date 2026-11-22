# Reads subagent logs from Claude Code and Antigravity, for agent-watch.sh
# and agent-stats.sh. Source it; needs jq and rg.

AGENT_LOG_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prints a log as Claude Code subagent log lines. An Antigravity transcript
# (its lines start with step_index) goes through antigravity-log.jq.
agent_log_lines() {
	local log="$1"
	if head -n 1 "${log}" | jq -e 'has("step_index")' > /dev/null 2>&1; then
		jq -sc -L "${AGENT_LOG_LIB}" --arg written "$(date -u -r "${log}" +%Y-%m-%dT%H:%M:%S.000Z)" \
			'include "antigravity-log"; claude_events($written)' "${log}"
	else
		cat "${log}"
	fi
}

# Prints the transcripts of the Antigravity subagents working in the folder
# $1 that changed in the last $2 minutes. A subagent's transcript does not
# say its folder; the transcript of the conversation that started it does.
antigravity_subagent_logs() {
	local root="$1" recent="$2" brain="${HOME}/.gemini/antigravity-cli/brain"
	[ -d "${brain}" ] || return 0
	rg -l -F --hidden --no-ignore --glob 'transcript.jsonl' 'Created the following subagent' "${brain}" 2> /dev/null \
		| while read -r parent; do
			jq -rs -L "${AGENT_LOG_LIB}" --arg root "${root}" \
				'include "antigravity-log"; started_subagents | select(.folders | index($root)) | .log' "${parent}"
		done \
		| sort -u \
		| while read -r log; do
			if [ -n "$(find "${log}" -mmin "-${recent}" 2> /dev/null)" ]; then
				printf '%s\n' "${log}"
			fi
		done
}

# A row name for a log: the Claude Code agent id, or the Antigravity
# conversation id (the folder three levels above transcript.jsonl).
agent_log_name() {
	local log="$1"
	case "${log}" in
		*/.system_generated/logs/transcript.jsonl) basename "$(dirname "$(dirname "$(dirname "${log}")")")" ;;
		*) basename "${log}" .jsonl ;;
	esac
}
