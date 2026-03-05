# Symphony GitHub + Claude Code Integration Design

Date: 2026-03-05
Status: Approved

## Goal

Customize Symphony to use GitHub Issues (with GitHub Projects kanban board) instead of Linear, and Claude Code instead of Codex, to automatically process bug/feature issues for a Java+Spring project on a local Mac.

## Requirements

- GitHub Issues as issue tracker (replacing Linear)
- GitHub Projects board for kanban state management (Todo, In Progress, Review, Done)
- Claude Code CLI as coding agent (replacing Codex app-server)
- Label-based filtering: `bug` for bug fixes, `feature` for feature work, `symphony` for auto-processing
- 5-10 concurrent agents, each with isolated workspace and independent branch
- Each agent picks up an issue, creates `symphony/#<number>` branch, works independently, creates PR
- Runs as local daemon on Mac

## Architecture

### Approach: Symphony Fork

Reuse existing orchestration logic (polling, concurrency, retry, workspace isolation) and replace two integration points:

1. `Tracker` adapter: Linear -> GitHub
2. Agent runner: Codex AppServer -> Claude Code CLI

### Flow

```
GitHub Projects Board (Kanban)
+----------+--------------+----------+--------+
|   Todo   | In Progress  |  Review  |  Done  |
|          |              |          |        |
| #12 bug  | #8 feat  <- Claude A   |        |
| #15 feat | #9 bug   <- Claude B   | #7 bug |
|          | #11 feat <- Claude C   |        |
+----------+--------------+----------+--------+

1. Orchestrator polls GitHub Projects API for Todo column issues
2. Claims issue: moves card to In Progress + adds `symphony` label
3. Creates workspace: ~/symphony-workspaces/#123/ -> git clone + git checkout -b symphony/#123
4. Runs Claude Code: `claude --print` in workspace with issue prompt
5. On completion: creates PR -> moves card to Review
6. Human merges -> card moves to Done
```

## New Modules

### `GitHub.Adapter` (`lib/symphony_elixir/github/adapter.ex`)

Implements `Tracker` behaviour. Delegates to `GitHub.Client`.

Callbacks:
- `fetch_candidate_issues/0` — queries Projects board Todo column
- `fetch_issues_by_states/1` — queries by column names
- `fetch_issue_states_by_ids/1` — checks current column for issue cards
- `create_comment/2` — posts comment on issue
- `update_issue_state/2` — moves card to target column

### `GitHub.Client` (`lib/symphony_elixir/github/client.ex`)

GitHub REST/GraphQL API communication via `req` HTTP client.

- Authentication: `GITHUB_TOKEN` environment variable
- Projects V2 GraphQL API for board/column operations
- REST API for issues, comments, labels, PRs

### `GitHub.Issue` (`lib/symphony_elixir/github/issue.ex`)

Converts GitHub API response to `Issue` struct:
- `id` -> GitHub issue node ID
- `identifier` -> `#123`
- `title` -> issue title
- `description` -> issue body
- `labels` -> GitHub labels (lowercase)
- `state` -> Projects board column name
- `branch_name` -> `symphony/#<number>`
- `url` -> issue HTML URL

### `ClaudeCode.Runner` (`lib/symphony_elixir/claude_code/runner.ex`)

Replaces `Codex.AppServer`. Runs Claude Code CLI via Erlang Port.

- Execution: `claude --print --verbose -p "<prompt>"` with workspace as cwd
- Multi-turn: `--resume <session_id>` for continuation turns
- Permissions: `--dangerously-skip-permissions` for autonomous mode
- Timeout: Port-level timeout matching `codex.turn_timeout_ms`
- Output: collects stdout text, reports to Orchestrator

## Modified Modules

### `Tracker` (`tracker.ex`)

Add `"github"` branch to `adapter/0`:

```elixir
def adapter do
  case Config.tracker_kind() do
    "memory" -> SymphonyElixir.Tracker.Memory
    "github" -> SymphonyElixir.GitHub.Adapter
    _ -> SymphonyElixir.Linear.Adapter
  end
end
```

### `Config` (`config.ex`)

- Add `tracker.kind: github` support
- Add GitHub-specific settings: `repo`, `project_number`, `filter_labels`, `auto_label`
- Add Claude Code settings: `agent.kind`, `agent.command`, `agent.permission_mode`
- Validate `GITHUB_TOKEN` when tracker kind is `github`

### `AgentRunner` (`agent_runner.ex`)

- Route to `ClaudeCode.Runner` instead of `Codex.AppServer` based on `agent.kind` config

### `PromptBuilder` (`prompt_builder.ex`)

- No structural change, just updated WORKFLOW.md prompt template

### `WORKFLOW.md`

Updated config and prompt for GitHub + Claude Code + Java/Spring context.

## Unchanged Modules

- `Orchestrator` — polling, concurrency, retry, reconciliation logic reused as-is
- `Workspace` — workspace isolation, hooks, symlink protection reused as-is
- `StatusDashboard` — terminal UI reused as-is
- `CLI` — entrypoint reused as-is
- Phoenix web dashboard — observability UI reused as-is

## Config Example

```yaml
tracker:
  kind: github
  repo: "my-org/my-spring-app"
  project_number: 1
  filter_labels:
    - bug
    - feature
  auto_label: symphony
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Closed
agent:
  kind: claude_code
  command: claude --print --verbose
  permission_mode: dangerously-skip-permissions
  max_concurrent_agents: 10
  max_turns: 20
workspace:
  root: ~/symphony-workspaces
hooks:
  after_create: |
    git clone git@github.com:my-org/my-spring-app.git .
    ./gradlew dependencies
```

Environment variables:
- `GITHUB_TOKEN` — GitHub API authentication
- `ANTHROPIC_API_KEY` — Claude Code API key

## Error Handling

### GitHub API
- Rate limit (5,000/hr): existing exponential backoff retry
- Issue closed mid-work: reconciliation loop detects -> stops agent + cleans workspace
- Column move failure: retry, then log warning
- Token permission issues: validate at startup

### Claude Code
- Process crash: Port exit detected -> failure report to Orchestrator -> backoff retry
- Turn timeout (default 1hr): process kill -> retry queue
- API key invalid: startup validation + runtime error logging
- `--resume` session not found: fallback to new session

### Workspace
- git clone failure: after_create hook fails -> no agent run -> retry
- Disk space: terminal issue workspaces auto-cleaned (existing logic)
- Branch conflicts: `symphony/#123` naming prevents collisions
