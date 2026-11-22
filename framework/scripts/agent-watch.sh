#!/usr/bin/env bash
# The observer's eyes: one row per subagent with what it is doing right now,
# read from its own log, and a flag where it needs a look.
#
#   framework/scripts/agent-watch.sh [options] [<log file> ...]
#
#   --idle <secs>     STALL when a running agent has been silent this long (90)
#   --budget <tokens> BUDGET when an agent has processed more than this (150000)
#   --lane <regex>    LANE when an agent edits a file the regex doesn't match
#   --recent <mins>   with no log files: agents active in this many minutes (30)
#   --session         also watch this project's newest main session (the Lead):
#                     SLOW only
#   --every <secs>    with --until-flag: how often to look (2)
#   --until-flag      keep watching; print and exit at the first new flag, or
#                     when every agent is done. Run it in the background.
#
# SLOW means one action is still running past the time it should take:
# lib/action-times.tsv gives each kind of action its seconds (a game adds
# or overrides lines in docs/team/action-times.tsv). It is flagged the
# moment it passes, e.g. a screenshot still going after 5 s. The overran
# column counts finished actions that took longer than their time.
#
# With no log files it takes this project's Claude Code and Antigravity
# subagent logs (an Antigravity transcript is read as a Claude Code log,
# see lib/antigravity-log.jq). LOOP means the
# same tool call was made three times or more. LANE and files_edited see only
# the Edit and Write tools; a file changed from the shell is invisible here,
# which is why the worker definitions tell agents to use Edit.
set -euo pipefail

idle=90
budget=150000
lane=""
recent=30
until_flag=no
session=no
every=2
while [ "$#" -gt 0 ]; do
	case "$1" in
		--idle) idle="$2"; shift 2 ;;
		--budget) budget="$2"; shift 2 ;;
		--lane) lane="$2"; shift 2 ;;
		--recent) recent="$2"; shift 2 ;;
		--session) session=yes; shift ;;
		--every) every="$2"; shift 2 ;;
		--until-flag) until_flag=yes; shift ;;
		*) break ;;
	esac
done

# Claude Code sessions run in the repository that holds the framework.
source "$(dirname "$0")/lib/game.sh"
source "$(dirname "$0")/lib/agent-log.sh"
root="$(cd "${FRAMEWORK}/.." && pwd)"
project="${HOME}/.claude/projects/$(printf '%s' "${root}" | sd '[^A-Za-z0-9]' '-')"

# Expected seconds per action as JSON [[regex, seconds], ...]: the game's
# lines first, so they win.
times="$(for file in "${root}/docs/team/action-times.tsv" "$(dirname "$0")/lib/action-times.tsv"; do
	if [ -f "${file}" ]; then cat "${file}"; fi
done | awk -F '\t' '!/^#/ && NF == 2 { print }' \
	| jq -Rsc '[split("\n")[] | select(. != "") | split("\t") | [.[0], (.[1] | tonumber)]]')"

logs() {
	if [ "$#" -gt 0 ]; then
		printf '%s\n' "$@"
		return
	fi
	find "${project}" -path '*/subagents/agent-*.jsonl' -mmin "-${recent}" 2> /dev/null | sort
	antigravity_subagent_logs "${root}" "${recent}"
	if [ "${session}" = yes ]; then
		find "${project}" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-
	fi
}

rows() {
	logs "$@" | while read -r log; do
		[ -f "${log}" ] || continue
		name="$(agent_log_name "${log}")"
		lead=no
		case "${log}" in */subagents/* | */.system_generated/logs/*) ;; *) lead=yes; name=lead ;; esac
		# The Lead's log can run to hundreds of MB; its last few MB hold the
		# recent actions, which is all SLOW needs (its counts cover that much).
		if [ "${lead}" = yes ]; then
			tail -c 4000000 "${log}" | tail -n +2
		else
			agent_log_lines "${log}"
		fi | jq -rs --arg name "${name#agent-}" --arg lead "${lead}" --argjson times "${times}" --argjson idle "${idle}" --argjson budget "${budget}" --arg lane "${lane}" '
			def seconds: (.[0:19] + "Z" | fromdate) + (.[20:23] | tonumber) / 1000;
			def context: .message.usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens;
			[.[] | select(.timestamp != null)] as $events
			| ([$events[] | select(.type == "assistant")]) as $said
			| ($said | unique_by(.message.id)) as $calls
			| [$said[] | .message.content[]? | select(.type == "tool_use")] as $uses
			| ($uses | group_by([.name, .input]) | map(length) | max // 0) as $repeat
			| ([$uses[] | select(.name == "Edit" or .name == "Write") | .input.file_path] | unique) as $edited
			| $events[-1] as $last
			# An agent ends its turn by handing its report back; a follow-up
			# message after that (a user event that is not a tool result) restarts it.
			| ([$events | to_entries[] | select(.value.type == "assistant" and any(.value.message.content[]?; .type == "tool_use" and .name == "SubagentHandback")) | .key] | last) as $handed
			| ($handed != null and ([$events[$handed + 1:][] | select(.type == "assistant" or (.type == "user" and ((.message.content | type) == "string" or any(.message.content[]?; .type == "text"))))] | length) == 0) as $done
			| ((now - ($last.timestamp | seconds)) | round) as $silent
			# Each action: when it started, when its result came (null: still
			# running) and the seconds it should take (0: no limit). Actions sent
			# in one message run one after another, so each starts when the one
			# before it in that message ended, not when the message was sent.
			| ($events | map(select(.type == "user") | .timestamp as $t | .message.content
				| if type == "array" then .[] else empty end | select(.type == "tool_result")
				| {key: .tool_use_id, value: ($t | seconds)}) | from_entries) as $ended
			| ([$events[] | select(.type == "assistant") | .timestamp as $t | .message.id as $message
				| .message.content[]? | select(.type == "tool_use")
				| {id, name, message: $message, command: (.input.command // "" | tostring), sent: ($t | seconds)}]
				| unique_by(.id) | sort_by(.sent) | .[-400:]
				| group_by(.message)
				| map(reduce .[] as $use ({out: [], after: null};
					($ended[$use.id]) as $end
					| ([$use.sent, (.after // $use.sent)] | max) as $start
					| .out += [$use + {start: $start, end: $end}]
					| .after = ($end // $start)) | .out)
				| add // []
				| map(. + {limit: ((.name + " " + .command) as $what
					| first($times[] | select(.[0] as $re | $what | test($re)) | .[1]) // 60)})) as $actions
			| [$actions[] | select(.limit > 0 and .end == null and (now - .start) > .limit)] as $slow
			| ([$actions[] | select(.limit > 0 and .end != null and (.end - .start) > .limit)] | length) as $overran
			| ([$calls[] | context] | add // 0) as $processed
			| [
				(if $done or $lead == "yes" then empty elif $silent > $idle then "STALL" else empty end),
				(if $done then empty else $slow[] | "SLOW:\(.name | sub("^mcp__[^_]+(-[^_]+)*__"; "")):\(now - .start | round)s>\(.limit)s" end),
				(if $lead == "no" and $repeat >= 3 then "LOOP" else empty end),
				(if $lead == "no" and $processed > $budget then "BUDGET" else empty end),
				(if $lane != "" and ([$edited[] | select(test($lane) | not)] | length) > 0 then "LANE" else empty end)
			] as $flags
			| [
				$name,
				($calls[0].message.model // "?"),
				(if $done then "done" else "running" end),
				$silent,
				($calls | length),
				$processed,
				$repeat,
				($edited | length),
				$overran,
				(if ($flags | length) > 0 then $flags | join(",") else "-" end)
			] | @tsv'
	done
}

table() {
	column -t -s $'\t' -N agent,model,state,silent,calls,tokens_processed,repeats,files_edited,overran,flags
}

if [ "${until_flag}" = no ]; then
	rows "$@" | table
	exit 0
fi

seen=""
while true; do
	current="$(rows "$@")"
	fresh="$(printf '%s\n' "${current}" | awk -F '\t' -v seen="${seen}" '$3 == "running" && $10 != "-" && index(seen, $1 ":" $10 ";") == 0')"
	if [ -n "${fresh}" ]; then
		printf '%s\n' "${fresh}" | table
		exit 0
	fi
	if [ -n "${current}" ] && ! printf '%s\n' "${current}" | awk -F '\t' '$3 == "running" { found = 1 } END { exit !found }'; then
		echo "every agent is done"
		printf '%s\n' "${current}" | table
		exit 0
	fi
	sleep "${every}"
done
