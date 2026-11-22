# Turns an Antigravity transcript (one step per line, read with jq -s) into
# the Claude Code subagent log lines agent-watch.sh and agent-stats.sh read:
# assistant events with usage and tool_use blocks, user events with tool
# results or text.
#
# Antigravity tools get the Claude names the scripts look for (Bash, Read,
# Edit, Write). A subagent reports with send_message and then ends its turn
# with a reply without tool calls; that reply gets a SubagentHandback block,
# the mark Claude Code leaves when a subagent hands its report back.

def stamp: .[0:19] + ".000Z";

def unhex: ascii_downcase | explode | reduce .[] as $c (0; . * 16 + (if $c >= 97 then $c - 87 else $c - 48 end));

def uri_path: sub("^file://"; "") | gsub("%(?<h>[0-9A-Fa-f]{2})"; [.h | unhex] | implode);

# A tool result's first "Created At: 2026-11-22T11:33:11+08:00" (when the
# tool started) or last "Completed At:", in UTC; null when it has none.
def result_time($which):
	[scan("\($which) At: ([0-9T:-]{19})([+-])([0-9]{2}):([0-9]{2})")]
	| (if $which == "Created" then first else last end) // null
	| if . == null then null else
		((.[0] + "Z" | fromdate) - (if .[1] == "+" then 1 else -1 end) * ((.[2] | tonumber) * 3600 + (.[3] | tonumber) * 60))
		| todate | stamp
	end;

# Tool arguments are stored JSON-encoded ("\"ls\"", "5000").
def claude_tool:
	(.args // {} | with_entries(.value |= (try fromjson catch .))) as $args
	| ($args.Path // $args.TargetFile // $args.AbsolutePath) as $file
	| if .name == "run_command" then {name: "Bash", input: ($args + {command: $args.CommandLine})}
	elif .name == "read_file" or .name == "view_file" then {name: "Read", input: ($args + {file_path: $file})}
	elif (.name | test("^(edit_file|replace_file_content|multi_replace_file_content)$")) then {name: "Edit", input: ($args + {file_path: $file})}
	elif .name == "write_file" or .name == "write_to_file" then {name: "Write", input: ($args + {file_path: $file})}
	else {name, input: $args}
	end;

# A step is stamped when the model starts writing it, but a Claude Code
# message is stamped when it is written, which is when its tools start. So a
# reply with tool calls is restamped with its first result's Created At or,
# while no result is in yet and it is the newest line, with $written (when
# the transcript file was last written).
def claude_events($written):
	reduce .[] as $step ({out: [], waiting: [], reported: false, reply: null, started: true};
		if $step.type == "PLANNER_RESPONSE" then
			([$step.tool_calls[]? | claude_tool] | to_entries | map(.value + {type: "tool_use", id: "\($step.step_index)-\(.key)"})) as $uses
			| (($uses | length) == 0 and .reported) as $handback
			| .out += [{
				type: "assistant",
				timestamp: ($step.created_at | stamp),
				message: {
					id: "step-\($step.step_index)",
					model: $step.model,
					usage: {
						input_tokens: ($step.input_tokens // 0),
						cache_creation_input_tokens: 0,
						cache_read_input_tokens: ($step.cache_read_tokens // 0),
						output_tokens: ($step.output_tokens // 0)
					},
					content: ($uses + (if $handback then [{type: "tool_use", id: "\($step.step_index)-handback", name: "SubagentHandback", input: {}}] else [] end))
				}
			}]
			| .reply = (.out | length - 1)
			| .started = (($uses | length) == 0)
			| .waiting = [$uses[].id]
			| .reported = (if $handback then false else .reported or any($uses[]; .name == "send_message") end)
		# One result step per tool call, in the order of the calls. A command
		# sent to the background has no Completed At: it returned at once.
		elif $step.type == "GENERIC" then
			($step.content // "") as $result
			| (if .started then . else
				.out[.reply].timestamp = ([.out[.reply].timestamp, ($result | result_time("Created"))] | max)
				| .started = true
			end)
			| .out += [{
				type: "user",
				timestamp: (($result | result_time("Completed")) // ($step.created_at | stamp)),
				message: {content: [{type: "tool_result", tool_use_id: .waiting[0]}]}
			}]
			| .waiting = .waiting[1:]
		elif $step.type == "SYSTEM_MESSAGE" or $step.type == "USER_INPUT" then
			.out += [{type: "user", timestamp: ($step.created_at | stamp), message: {content: ($step.content // "")}}]
		else
			.
		end)
	| if .started or .reply != (.out | length - 1) or $written == null then . else
		.out[.reply].timestamp = ([.out[.reply].timestamp, $written] | max)
	end
	| .out[];

# The subagents a transcript started: {log, folders} from each
# "Created the following subagent:" result.
def started_subagents:
	.[] | select(.type == "GENERIC") | .content // ""
	| select(contains("Created the following subagent"))
	| capture("subagent:\\s*(?<json>\\{[^}]*\\})").json | fromjson
	| {log: (.logAbsoluteUri | uri_path), folders: [.workspaceUris[]? | uri_path]};
