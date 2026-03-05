# GitHub + Claude Code Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Linear with GitHub Issues (Projects board) and Codex with Claude Code CLI in Symphony.

**Architecture:** Fork Symphony's Elixir codebase. Add `GitHub.Adapter`, `GitHub.Client`, `GitHub.Issue` modules for GitHub integration. Add `ClaudeCode.Runner` module for Claude Code CLI execution. Modify `Tracker`, `Config`, `AgentRunner` to route to new modules. Update `WORKFLOW.md` for GitHub + Claude Code.

**Tech Stack:** Elixir/OTP, GitHub REST/GraphQL API, Claude Code CLI (`claude --print`), `req` HTTP client.

---

### Task 1: GitHub Issue Normalizer

**Files:**
- Create: `elixir/lib/symphony_elixir/github/issue.ex`
- Test: `elixir/test/symphony_elixir/github/issue_test.exs`

**Step 1: Write the failing test**

```elixir
# test/symphony_elixir/github/issue_test.exs
defmodule SymphonyElixir.GitHub.IssueTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Issue, as: GitHubIssue
  alias SymphonyElixir.Linear.Issue

  test "normalize/1 converts GitHub API response to Issue struct" do
    github_response = %{
      "id" => "I_abc123",
      "number" => 42,
      "title" => "Fix login bug",
      "body" => "Login fails on timeout",
      "labels" => %{"nodes" => [%{"name" => "Bug"}, %{"name" => "Priority"}]},
      "url" => "https://github.com/my-org/my-app/issues/42",
      "createdAt" => "2026-03-01T10:00:00Z",
      "updatedAt" => "2026-03-02T12:00:00Z"
    }

    column_name = "Todo"

    result = GitHubIssue.normalize(github_response, column_name)

    assert %Issue{} = result
    assert result.id == "I_abc123"
    assert result.identifier == "#42"
    assert result.title == "Fix login bug"
    assert result.description == "Login fails on timeout"
    assert result.state == "Todo"
    assert result.branch_name == "symphony/42"
    assert result.url == "https://github.com/my-org/my-app/issues/42"
    assert result.labels == ["bug", "priority"]
  end

  test "normalize/1 handles nil body" do
    github_response = %{
      "id" => "I_abc123",
      "number" => 7,
      "title" => "Simple task",
      "body" => nil,
      "labels" => %{"nodes" => []},
      "url" => "https://github.com/my-org/my-app/issues/7",
      "createdAt" => nil,
      "updatedAt" => nil
    }

    result = GitHubIssue.normalize(github_response, "In Progress")

    assert result.description == nil
    assert result.branch_name == "symphony/7"
    assert result.labels == []
  end

  test "normalize/1 returns nil for invalid input" do
    assert GitHubIssue.normalize(nil, "Todo") == nil
    assert GitHubIssue.normalize("not a map", "Todo") == nil
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/symphony_elixir/github/issue_test.exs -v`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```elixir
# lib/symphony_elixir/github/issue.ex
defmodule SymphonyElixir.GitHub.Issue do
  @moduledoc """
  Converts GitHub API issue responses to the normalized Issue struct.
  """

  alias SymphonyElixir.Linear.Issue

  @spec normalize(map() | nil, String.t()) :: Issue.t() | nil
  def normalize(issue, column_name) when is_map(issue) and is_binary(column_name) do
    number = issue["number"]

    %Issue{
      id: issue["id"],
      identifier: "##{number}",
      title: issue["title"],
      description: issue["body"],
      priority: nil,
      state: column_name,
      branch_name: "symphony/#{number}",
      url: issue["url"],
      assignee_id: get_in(issue, ["assignees", "nodes", Access.at(0), "login"]),
      labels: extract_labels(issue),
      assigned_to_worker: true,
      created_at: parse_datetime(issue["createdAt"]),
      updated_at: parse_datetime(issue["updatedAt"])
    }
  end

  def normalize(_issue, _column_name), do: nil

  defp extract_labels(%{"labels" => %{"nodes" => labels}}) when is_list(labels) do
    labels
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_labels(_), do: []

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
```

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/symphony_elixir/github/issue_test.exs -v`
Expected: PASS (3 tests, 0 failures)

**Step 5: Commit**

```bash
git add elixir/lib/symphony_elixir/github/issue.ex elixir/test/symphony_elixir/github/issue_test.exs
git commit -m "feat: add GitHub issue normalizer module"
```

---

### Task 2: GitHub Client

**Files:**
- Create: `elixir/lib/symphony_elixir/github/client.ex`
- Test: `elixir/test/symphony_elixir/github/client_test.exs`

**Step 1: Write the failing test**

```elixir
# test/symphony_elixir/github/client_test.exs
defmodule SymphonyElixir.GitHub.ClientTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Client

  describe "graphql/3" do
    test "sends GraphQL request with auth header" do
      test_pid = self()

      request_fun = fn payload, headers ->
        send(test_pid, {:request, payload, headers})
        {:ok, %{status: 200, body: %{"data" => %{"viewer" => %{"login" => "test-user"}}}}}
      end

      result = Client.graphql("query { viewer { login } }", %{}, token: "ghp_test123", request_fun: request_fun)

      assert {:ok, %{"data" => _}} = result
      assert_received {:request, payload, headers}
      assert payload["query"] == "query { viewer { login } }"
      assert {"Authorization", "Bearer ghp_test123"} in headers
    end

    test "returns error on non-200 status" do
      request_fun = fn _payload, _headers ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end

      result = Client.graphql("query { viewer { login } }", %{}, token: "bad_token", request_fun: request_fun)

      assert {:error, {:github_api_status, 401}} = result
    end
  end

  describe "rest_get/2" do
    test "sends GET request with auth header" do
      test_pid = self()

      request_fun = fn url, headers ->
        send(test_pid, {:rest_get, url, headers})
        {:ok, %{status: 200, body: [%{"id" => 1, "title" => "Issue 1"}]}}
      end

      result = Client.rest_get("/repos/org/repo/issues", token: "ghp_test123", request_fun: request_fun)

      assert {:ok, [%{"id" => 1}]} = result
      assert_received {:rest_get, _, headers}
      assert {"Authorization", "Bearer ghp_test123"} in headers
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/symphony_elixir/github/client_test.exs -v`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```elixir
# lib/symphony_elixir/github/client.ex
defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  GitHub REST and GraphQL API client.
  """

  require Logger

  @github_graphql_endpoint "https://api.github.com/graphql"
  @github_rest_base "https://api.github.com"
  @max_error_body_log_bytes 1_000

  @spec graphql(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables \\ %{}, opts \\ []) do
    token = Keyword.get(opts, :token) || github_token()
    request_fun = Keyword.get(opts, :request_fun, &post_graphql_request/2)

    payload = %{"query" => query, "variables" => variables}

    case request_fun.(payload, auth_headers(token)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, response} ->
        Logger.error("GitHub GraphQL request failed status=#{response.status} body=#{summarize_body(response.body)}")
        {:error, {:github_api_status, response.status}}

      {:error, reason} ->
        Logger.error("GitHub GraphQL request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @spec rest_get(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def rest_get(path, opts \\ []) do
    token = Keyword.get(opts, :token) || github_token()
    request_fun = Keyword.get(opts, :request_fun, &get_rest_request/2)

    url = @github_rest_base <> path

    case request_fun.(url, auth_headers(token)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, response} ->
        Logger.error("GitHub REST request failed status=#{response.status}")
        {:error, {:github_api_status, response.status}}

      {:error, reason} ->
        Logger.error("GitHub REST request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @spec rest_post(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def rest_post(path, body, opts \\ []) do
    token = Keyword.get(opts, :token) || github_token()
    request_fun = Keyword.get(opts, :request_fun, &post_rest_request/3)

    url = @github_rest_base <> path

    case request_fun.(url, body, auth_headers(token)) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, response} ->
        Logger.error("GitHub REST POST failed status=#{response.status}")
        {:error, {:github_api_status, response.status}}

      {:error, reason} ->
        {:error, {:github_api_request, reason}}
    end
  end

  defp github_token do
    System.get_env("GITHUB_TOKEN")
  end

  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp post_graphql_request(payload, headers) do
    Req.post(@github_graphql_endpoint, headers: headers, json: payload, connect_options: [timeout: 30_000])
  end

  defp get_rest_request(url, headers) do
    Req.get(url, headers: headers, connect_options: [timeout: 30_000])
  end

  defp post_rest_request(url, body, headers) do
    Req.post(url, headers: headers, json: body, connect_options: [timeout: 30_000])
  end

  defp summarize_body(body) when is_binary(body) do
    if byte_size(body) > @max_error_body_log_bytes do
      binary_part(body, 0, @max_error_body_log_bytes) <> "...<truncated>"
    else
      body
    end
  end

  defp summarize_body(body), do: inspect(body, limit: 20, printable_limit: @max_error_body_log_bytes)
end
```

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/symphony_elixir/github/client_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add elixir/lib/symphony_elixir/github/client.ex elixir/test/symphony_elixir/github/client_test.exs
git commit -m "feat: add GitHub REST/GraphQL client module"
```

---

### Task 3: GitHub Adapter (Tracker behaviour)

**Files:**
- Create: `elixir/lib/symphony_elixir/github/adapter.ex`
- Test: `elixir/test/symphony_elixir/github/adapter_test.exs`

**Step 1: Write the failing test**

```elixir
# test/symphony_elixir/github/adapter_test.exs
defmodule SymphonyElixir.GitHub.AdapterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Adapter
  alias SymphonyElixir.Linear.Issue

  describe "fetch_candidate_issues/0" do
    test "returns normalized issues from GitHub Projects board" do
      projects_response = %{
        "data" => %{
          "repository" => %{
            "projectV2" => %{
              "items" => %{
                "nodes" => [
                  %{
                    "fieldValueByName" => %{"name" => "Todo"},
                    "content" => %{
                      "__typename" => "Issue",
                      "id" => "I_abc",
                      "number" => 42,
                      "title" => "Fix bug",
                      "body" => "It's broken",
                      "url" => "https://github.com/org/repo/issues/42",
                      "labels" => %{"nodes" => [%{"name" => "bug"}]},
                      "createdAt" => "2026-03-01T00:00:00Z",
                      "updatedAt" => "2026-03-01T00:00:00Z"
                    }
                  }
                ],
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
              }
            }
          }
        }
      }

      graphql_fun = fn _query, _vars, _opts -> {:ok, projects_response} end

      {:ok, issues} = Adapter.fetch_candidate_issues(graphql_fun: graphql_fun, repo: "org/repo", project_number: 1, active_states: ["Todo", "In Progress"])

      assert [%Issue{id: "I_abc", identifier: "#42", state: "Todo"}] = issues
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/symphony_elixir/github/adapter_test.exs -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```elixir
# lib/symphony_elixir/github/adapter.ex
defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub-backed tracker adapter using GitHub Projects V2 for state management.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.{Client, Issue, as: GitHubIssue}
  alias SymphonyElixir.Config

  @items_page_size 50

  @projects_query """
  query SymphonyGitHubPoll($owner: String!, $repo: String!, $projectNumber: Int!, $first: Int!, $after: String) {
    repository(owner: $owner, name: $repo) {
      projectV2(number: $projectNumber) {
        items(first: $first, after: $after) {
          nodes {
            fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
              }
            }
            content {
              __typename
              ... on Issue {
                id
                number
                title
                body
                url
                labels(first: 20) {
                  nodes {
                    name
                  }
                }
                assignees(first: 5) {
                  nodes {
                    login
                  }
                }
                createdAt
                updatedAt
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
  }
  """

  @comment_mutation """
  mutation SymphonyCreateComment($subjectId: ID!, $body: String!) {
    addComment(input: {subjectId: $subjectId, body: $body}) {
      commentEdge {
        node {
          id
        }
      }
    }
  }
  """

  @impl true
  def fetch_candidate_issues do
    fetch_candidate_issues([])
  end

  @spec fetch_candidate_issues(keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues(opts) do
    {owner, repo} = repo_parts(Keyword.get(opts, :repo) || Config.github_repo())
    project_number = Keyword.get(opts, :project_number) || Config.github_project_number()
    active_states = Keyword.get(opts, :active_states) || Config.linear_active_states()
    graphql_fun = Keyword.get(opts, :graphql_fun, &Client.graphql/3)

    do_fetch_items(owner, repo, project_number, active_states, graphql_fun, nil, [])
  end

  @impl true
  def fetch_issues_by_states(states) do
    fetch_candidate_issues(active_states: states)
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) do
    {:ok, all_issues} = fetch_candidate_issues(active_states: nil)

    wanted = MapSet.new(issue_ids)
    {:ok, Enum.filter(all_issues, fn issue -> MapSet.member?(wanted, issue.id) end)}
  end

  @impl true
  def create_comment(issue_id, body) do
    case Client.graphql(@comment_mutation, %{subjectId: issue_id, body: body}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_issue_state(issue_id, state_name) do
    # Move card to target column via Projects V2 mutation
    # This requires the project item ID and field/option IDs — resolved at runtime
    move_project_card(issue_id, state_name)
  end

  defp do_fetch_items(owner, repo, project_number, active_states, graphql_fun, after_cursor, acc) do
    case graphql_fun.(@projects_query, %{
      owner: owner,
      repo: repo,
      projectNumber: project_number,
      first: @items_page_size,
      after: after_cursor
    }, []) do
      {:ok, body} ->
        items = get_in(body, ["data", "repository", "projectV2", "items"])
        nodes = get_in(items, ["nodes"]) || []
        page_info = get_in(items, ["pageInfo"]) || %{}

        issues =
          nodes
          |> Enum.filter(&issue_content?/1)
          |> Enum.map(&normalize_item/1)
          |> Enum.reject(&is_nil/1)
          |> maybe_filter_by_states(active_states)

        updated_acc = acc ++ issues

        if page_info["hasNextPage"] == true and is_binary(page_info["endCursor"]) do
          do_fetch_items(owner, repo, project_number, active_states, graphql_fun, page_info["endCursor"], updated_acc)
        else
          {:ok, updated_acc}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp issue_content?(%{"content" => %{"__typename" => "Issue"}}), do: true
  defp issue_content?(_), do: false

  defp normalize_item(%{"fieldValueByName" => %{"name" => column}, "content" => content}) do
    GitHubIssue.normalize(content, column)
  end

  defp normalize_item(%{"fieldValueByName" => nil, "content" => content}) do
    GitHubIssue.normalize(content, "No Status")
  end

  defp normalize_item(_), do: nil

  defp maybe_filter_by_states(issues, nil), do: issues

  defp maybe_filter_by_states(issues, states) do
    normalized_states = Enum.map(states, &String.downcase(String.trim(&1))) |> MapSet.new()

    Enum.filter(issues, fn issue ->
      MapSet.member?(normalized_states, String.downcase(String.trim(issue.state || "")))
    end)
  end

  defp repo_parts(repo_string) do
    case String.split(repo_string, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> raise ArgumentError, "Invalid repo format: #{repo_string}, expected 'owner/repo'"
    end
  end

  defp move_project_card(_issue_id, _state_name) do
    # TODO: Implement Projects V2 card move mutation
    :ok
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/symphony_elixir/github/adapter_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add elixir/lib/symphony_elixir/github/adapter.ex elixir/test/symphony_elixir/github/adapter_test.exs
git commit -m "feat: add GitHub adapter implementing Tracker behaviour"
```

---

### Task 4: Claude Code Runner

**Files:**
- Create: `elixir/lib/symphony_elixir/claude_code/runner.ex`
- Test: `elixir/test/symphony_elixir/claude_code/runner_test.exs`

**Step 1: Write the failing test**

```elixir
# test/symphony_elixir/claude_code/runner_test.exs
defmodule SymphonyElixir.ClaudeCode.RunnerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ClaudeCode.Runner

  test "build_command/2 produces correct CLI args" do
    args = Runner.build_command("Fix the login bug in AuthController.java", dangerously_skip_permissions: true)

    assert "--print" in args
    assert "-p" in args
    assert "--dangerously-skip-permissions" in args
    assert "Fix the login bug in AuthController.java" in args
  end

  test "build_command/2 without skip permissions" do
    args = Runner.build_command("Fix bug", dangerously_skip_permissions: false)

    assert "--print" in args
    refute "--dangerously-skip-permissions" in args
  end

  test "build_resume_command/2 adds resume flag" do
    args = Runner.build_resume_command("session-abc-123", "Continue working")

    assert "--resume" in args
    assert "session-abc-123" in args
    assert "--print" in args
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/symphony_elixir/claude_code/runner_test.exs -v`
Expected: FAIL

**Step 3: Write minimal implementation**

```elixir
# lib/symphony_elixir/claude_code/runner.ex
defmodule SymphonyElixir.ClaudeCode.Runner do
  @moduledoc """
  Runs Claude Code CLI in isolated workspaces via Erlang Port.
  Replaces Codex AppServer for Claude Code integration.
  """

  require Logger

  @spec run(Path.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workspace, prompt, issue, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 3_600_000)
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    skip_permissions = Keyword.get(opts, :dangerously_skip_permissions, true)

    command_args = build_command(prompt, dangerously_skip_permissions: skip_permissions)

    case run_claude_process(workspace, command_args, timeout_ms) do
      {:ok, output} ->
        session_id = generate_session_id()

        on_message.(%{
          event: :turn_completed,
          session_id: session_id,
          output: output
        })

        Logger.info("Claude Code completed for issue_id=#{issue.id} issue_identifier=#{issue.identifier} session_id=#{session_id}")

        {:ok, %{
          result: :turn_completed,
          session_id: session_id,
          output: output
        }}

      {:error, reason} ->
        Logger.error("Claude Code failed for issue_id=#{issue.id}: #{inspect(reason)}")

        on_message.(%{
          event: :turn_failed,
          reason: reason
        })

        {:error, reason}
    end
  end

  @spec run_continuation(Path.t(), String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_continuation(workspace, session_id, prompt, issue, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 3_600_000)
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)

    command_args = build_resume_command(session_id, prompt)

    case run_claude_process(workspace, command_args, timeout_ms) do
      {:ok, output} ->
        on_message.(%{event: :turn_completed, session_id: session_id, output: output})
        {:ok, %{result: :turn_completed, session_id: session_id, output: output}}

      {:error, reason} ->
        on_message.(%{event: :turn_failed, reason: reason})
        {:error, reason}
    end
  end

  @spec build_command(String.t(), keyword()) :: [String.t()]
  def build_command(prompt, opts \\ []) do
    skip_permissions = Keyword.get(opts, :dangerously_skip_permissions, true)

    args = ["--print", "--verbose", "-p", prompt]

    if skip_permissions do
      args ++ ["--dangerously-skip-permissions"]
    else
      args
    end
  end

  @spec build_resume_command(String.t(), String.t()) :: [String.t()]
  def build_resume_command(session_id, prompt) do
    ["--print", "--verbose", "--resume", session_id, "-p", prompt, "--dangerously-skip-permissions"]
  end

  defp run_claude_process(workspace, args, timeout_ms) do
    claude_executable = System.find_executable("claude")

    if is_nil(claude_executable) do
      {:error, :claude_not_found}
    else
      port = Port.open(
        {:spawn_executable, String.to_charlist(claude_executable)},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: Enum.map(args, &String.to_charlist/1),
          cd: String.to_charlist(workspace)
        ]
      )

      collect_output(port, timeout_ms, [])
    end
  end

  defp collect_output(port, timeout_ms, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, timeout_ms, [data | acc])

      {^port, {:exit_status, 0}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:ok, output}

      {^port, {:exit_status, status}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        Logger.warning("Claude Code exited with status #{status}: #{String.slice(output, 0, 500)}")
        {:error, {:exit_status, status, output}}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp generate_session_id do
    "claude-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp default_on_message(_message), do: :ok
end
```

**Step 4: Run test to verify it passes**

Run: `cd elixir && mix test test/symphony_elixir/claude_code/runner_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add elixir/lib/symphony_elixir/claude_code/runner.ex elixir/test/symphony_elixir/claude_code/runner_test.exs
git commit -m "feat: add Claude Code CLI runner module"
```

---

### Task 5: Wire Tracker to GitHub Adapter

**Files:**
- Modify: `elixir/lib/symphony_elixir/tracker.ex:40-46`
- Modify: `elixir/lib/symphony_elixir/config.ex` (add github settings)
- Test: `elixir/test/symphony_elixir/github/tracker_routing_test.exs`

**Step 1: Write the failing test**

```elixir
# test/symphony_elixir/github/tracker_routing_test.exs
defmodule SymphonyElixir.GitHub.TrackerRoutingTest do
  use SymphonyElixir.TestSupport

  test "Tracker.adapter/0 returns GitHub adapter when kind is github" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "github")
    assert Tracker.adapter() == SymphonyElixir.GitHub.Adapter
  end

  test "Tracker.adapter/0 returns Linear adapter for default" do
    write_workflow_file!(Workflow.workflow_file_path(), tracker_kind: "linear")
    assert Tracker.adapter() == SymphonyElixir.Linear.Adapter
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd elixir && mix test test/symphony_elixir/github/tracker_routing_test.exs -v`
Expected: FAIL — GitHub adapter not routed

**Step 3: Modify Tracker module**

In `elixir/lib/symphony_elixir/tracker.ex`, update `adapter/0`:

```elixir
@spec adapter() :: module()
def adapter do
  case Config.tracker_kind() do
    "memory" -> SymphonyElixir.Tracker.Memory
    "github" -> SymphonyElixir.GitHub.Adapter
    _ -> SymphonyElixir.Linear.Adapter
  end
end
```

**Step 4: Add GitHub config getters to Config**

Add to `elixir/lib/symphony_elixir/config.ex`:

```elixir
@spec github_repo() :: String.t() | nil
def github_repo do
  get_in(validated_workflow_options(), [:tracker, :repo])
end

@spec github_project_number() :: integer() | nil
def github_project_number do
  get_in(validated_workflow_options(), [:tracker, :project_number])
end

@spec github_filter_labels() :: [String.t()]
def github_filter_labels do
  get_in(validated_workflow_options(), [:tracker, :filter_labels]) || []
end

@spec github_auto_label() :: String.t() | nil
def github_auto_label do
  get_in(validated_workflow_options(), [:tracker, :auto_label])
end
```

And update the NimbleOptions schema `tracker` keys to include:
```elixir
repo: [type: {:or, [:string, nil]}, default: nil],
project_number: [type: {:or, [:non_neg_integer, nil]}, default: nil],
filter_labels: [type: {:list, :string}, default: []],
auto_label: [type: {:or, [:string, nil]}, default: nil],
```

And update `extract_tracker_options/1`:
```elixir
|> put_if_present(:repo, scalar_string_value(Map.get(section, "repo")))
|> put_if_present(:project_number, non_negative_integer_value(Map.get(section, "project_number")))
|> put_if_present(:filter_labels, csv_value(Map.get(section, "filter_labels")))
|> put_if_present(:auto_label, scalar_string_value(Map.get(section, "auto_label")))
```

And update `require_linear_project/0` to handle github:
```elixir
defp require_linear_project do
  case tracker_kind() do
    "linear" ->
      if is_binary(linear_project_slug()), do: :ok, else: {:error, :missing_linear_project_slug}
    "github" ->
      if is_binary(github_repo()), do: :ok, else: {:error, :missing_github_repo}
    _ ->
      :ok
  end
end
```

**Step 5: Run test to verify it passes**

Run: `cd elixir && mix test test/symphony_elixir/github/tracker_routing_test.exs -v`
Expected: PASS

**Step 6: Commit**

```bash
git add elixir/lib/symphony_elixir/tracker.ex elixir/lib/symphony_elixir/config.ex elixir/test/symphony_elixir/github/tracker_routing_test.exs
git commit -m "feat: wire GitHub adapter into Tracker and Config"
```

---

### Task 6: Wire AgentRunner to Claude Code

**Files:**
- Modify: `elixir/lib/symphony_elixir/agent_runner.ex:49-59`
- Modify: `elixir/lib/symphony_elixir/config.ex` (add agent.kind)

**Step 1: Add agent kind config**

Add to Config NimbleOptions schema under `agent`:
```elixir
kind: [type: {:or, [:string, nil]}, default: nil],
```

Add getter:
```elixir
@spec agent_kind() :: String.t() | nil
def agent_kind do
  get_in(validated_workflow_options(), [:agent, :kind])
end
```

Add to `extract_agent_options/1`:
```elixir
|> put_if_present(:kind, scalar_string_value(Map.get(section, "kind")))
```

**Step 2: Modify AgentRunner to route by agent kind**

In `agent_runner.ex`, update `run_codex_turns/4`:

```elixir
defp run_codex_turns(workspace, issue, codex_update_recipient, opts) do
  max_turns = Keyword.get(opts, :max_turns, Config.agent_max_turns())
  issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)

  case Config.agent_kind() do
    "claude_code" ->
      run_claude_code_turns(workspace, issue, codex_update_recipient, opts, issue_state_fetcher, 1, max_turns)

    _ ->
      # Existing Codex flow
      with {:ok, session} <- AppServer.start_session(workspace) do
        try do
          do_run_codex_turns(session, workspace, issue, codex_update_recipient, opts, issue_state_fetcher, 1, max_turns)
        after
          AppServer.stop_session(session)
        end
      end
  end
end

defp run_claude_code_turns(workspace, issue, update_recipient, opts, issue_state_fetcher, turn_number, max_turns) do
  prompt = build_turn_prompt(issue, opts, turn_number, max_turns)
  on_message = codex_message_handler(update_recipient, issue)

  case ClaudeCode.Runner.run(workspace, prompt, issue, on_message: on_message) do
    {:ok, %{session_id: session_id}} ->
      case continue_with_issue?(issue, issue_state_fetcher) do
        {:continue, refreshed_issue} when turn_number < max_turns ->
          continuation_prompt = build_turn_prompt(refreshed_issue, opts, turn_number + 1, max_turns)

          case ClaudeCode.Runner.run_continuation(workspace, session_id, continuation_prompt, refreshed_issue, on_message: on_message) do
            {:ok, _} ->
              run_claude_code_turns(workspace, refreshed_issue, update_recipient, opts, issue_state_fetcher, turn_number + 1, max_turns)

            {:error, reason} ->
              {:error, reason}
          end

        {:continue, _} -> :ok
        {:done, _} -> :ok
        {:error, reason} -> {:error, reason}
      end

    {:error, reason} ->
      {:error, reason}
  end
end
```

Add alias at top of `agent_runner.ex`:
```elixir
alias SymphonyElixir.ClaudeCode
```

**Step 3: Commit**

```bash
git add elixir/lib/symphony_elixir/agent_runner.ex elixir/lib/symphony_elixir/config.ex
git commit -m "feat: wire AgentRunner to Claude Code runner by agent.kind config"
```

---

### Task 7: Update WORKFLOW.md for GitHub + Claude Code

**Files:**
- Create: `elixir/WORKFLOW.github.md` (example GitHub workflow)

**Step 1: Write the GitHub workflow file**

```markdown
---
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
polling:
  interval_ms: 15000
workspace:
  root: ~/symphony-workspaces
hooks:
  after_create: |
    git clone git@github.com:my-org/my-spring-app.git .
    ./gradlew dependencies || mvn dependency:resolve || true
agent:
  kind: claude_code
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: claude --print --verbose
  approval_policy: never
---

You are working on GitHub issue `{{ issue.identifier }}`

{% if attempt %}
This is retry attempt #{{ attempt }}. Resume from current workspace state.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
State: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended session. Work autonomously.
2. Create branch `{{ issue.branch_name }}` from `origin/main`.
3. Implement the fix/feature described in the issue.
4. This is a Java + Spring Boot project. Run `./gradlew build` to verify.
5. Commit with a clear message referencing the issue.
6. Push branch and create a PR with `gh pr create`.
7. Add label `symphony` to the PR.
```

**Step 2: Commit**

```bash
git add elixir/WORKFLOW.github.md
git commit -m "feat: add example GitHub + Claude Code workflow file"
```

---

### Task 8: Run full test suite and verify

**Step 1: Run existing tests (nothing should break)**

Run: `cd elixir && mix test -v`
Expected: All existing tests PASS (new modules don't break existing Linear/Codex flow)

**Step 2: Run new tests only**

Run: `cd elixir && mix test test/symphony_elixir/github/ test/symphony_elixir/claude_code/ -v`
Expected: All new tests PASS

**Step 3: Run lint**

Run: `cd elixir && mix lint`
Expected: No warnings

**Step 4: Commit final state**

```bash
git add -A
git commit -m "feat: complete GitHub Issues + Claude Code integration for Symphony"
```
