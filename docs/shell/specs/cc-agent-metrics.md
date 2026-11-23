# Spec: agent metrics and away history

Two local, read-only producers. Python computes; the UI only draws.
Nothing leaves the machine. No prompt text, message content, cwd or path is ever stored.

---

## 1. `agent-metrics.json`

| Item | Value |
|---|---|
| Path | `~/.local/state/dots-overview/agent-metrics.json` (`0600`, atomic) |
| Writer | `dots_overview/agent_metrics.py` (`python3 -m dots_overview.agent_metrics`) |
| Version | `"v": 1`, plus `ts`, `today`, `costIsEstimate: true` |
| Day | A work session's `attendance_day` when the time falls in one, else local date |

Sources (read-only):

1. Transcripts `~/.claude/projects/*/<session>.jsonl` and `<session>/subagents/*.jsonl`
   → `message.usage`, `message.model`, `message.id`, timestamp only.
2. Session ledger `sessions.jsonl` → agent name, ticket, prompt/stop times.
3. `work.db` `work_session` → day mapping (optional).
4. `herdr agent list` → `live` counts (optional, 3 s timeout).

Top level: `days` (last 30, oldest first), `periods.{today,week,month}`, `prices`, `live`.

Each `days[]` and period carries: `runs`, `prompts`, `activeMin`, `waitingMin`,
`tokens{in,out,cacheWrite,cacheRead,total,msgs}`, `costUsd`, `subagentShare`.
Periods add `prev` (the equal span before), `delta` (cur minus prev), `unpricedTokens`,
and `byAgent`, `byTicket`, `byModel` (top 25 by tokens).

Definitions:

| Metric | Rule |
|---|---|
| runs | sessions with a prompt or tokens in the span |
| activeMin | prompt → next stop; capped 3 h; an open prompt runs to now |
| waitingMin | stop → next prompt; capped 60 min. An approximation of "waiting on you" |
| subagentShare | subagent-transcript tokens ÷ all tokens |
| week / month | last 7 / 30 days incl. today; prev = the 7 / 30 before |

Cost is an **estimate**: the `PRICES` table at the top of the module, USD per million
tokens (input, output, cache write, cache read). Edit it there. A model with no row keeps
its tokens, adds to `unpricedTokens`, and has `costUsd: null`. A total with unpriced
tokens is a floor.

Incremental: `agent-metrics-cache/tokens.json` holds, per transcript, the byte offset read
and per-day per-model sums. Later runs read only appended bytes. A shrunk file is re-read.
A message written more than once (streaming) is counted once, the last write winning.

---

## 2. `away.json`

| Item | Value |
|---|---|
| Path | `~/.local/state/dots-overview/away.json` (`0600`, atomic) |
| Writer | `dots_overview/away_history.py` |
| Span | last 7 days; gaps under 60 s dropped |
| Sources | `work.db` (`deduction`, `clock_event` away kinds) and `private.db` (`away_label`), both `mode=ro` |

Each gap: `startTs`, `endTs`, `minutes`, `day`, `category`, `label`, `answered`, `source`.

- `category` comes from the overlapping deduction (`salah`, `lunch`, `washroom`, ...), else the label key.
- `answered` is true for a `declared` or `asked` label, or a confirmed deduction.
  An `auto` label or an unconfirmed deduction is unanswered.
- Totals: `count`, `answered`, `unanswered`, `totalMin`, `byCategory`.

---

## 3. Wiring

One line each in the `dots-overview` fast cycle (see `cli.py`), same pattern as `heatmap`:
call `agent_metrics.run()` and `away_history.run()`. Both write their own file.
