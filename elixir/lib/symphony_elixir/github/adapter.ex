defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub Projects V2 backed tracker adapter.

  Implements the `SymphonyElixir.Tracker` behaviour by querying a GitHub
  Projects V2 board via the GraphQL API.  Issues are filtered by their
  board column (Status field) to determine state.

  All public functions accept an `opts` keyword list for dependency injection:

    * `:graphql_fun` — `(query, variables) -> {:ok, map()} | {:error, term()}`
    * `:owner` — GitHub repository owner
    * `:repo` — GitHub repository name
    * `:project_number` — Projects V2 board number
    * `:active_states` — list of column names considered active (default: config)

  The zero-arity `@behaviour` callbacks read from application config.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.{Client, Issue}

  @default_active_states ["Todo", "In Progress"]
  @page_size 100

  @project_items_query """
  query($owner: String!, $repo: String!, $projectNumber: Int!, $first: Int!, $after: String) {
    repository(owner: $owner, name: $repo) {
      projectV2(number: $projectNumber) {
        items(first: $first, after: $after) {
          nodes {
            fieldValueByName(name: "Status") {
              ... on ProjectV2ItemFieldSingleSelectValue { name }
            }
            content {
              __typename
              ... on Issue {
                id
                number
                title
                body
                url
                labels(first: 20) { nodes { name } }
                createdAt
                updatedAt
              }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
  """

  @add_comment_mutation """
  mutation($subjectId: ID!, $body: String!) {
    addComment(input: {subjectId: $subjectId, body: $body}) {
      commentEdge { node { id } }
    }
  }
  """

  # ---------------------------------------------------------------------------
  # Behaviour callbacks (0-arity — read config)
  # ---------------------------------------------------------------------------

  @impl true
  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    fetch_candidate_issues(config_opts())
  end

  @impl true
  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    fetch_issues_by_states(states, config_opts())
  end

  @impl true
  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    fetch_issue_states_by_ids(issue_ids, config_opts())
  end

  @impl true
  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    create_comment(issue_id, body, config_opts())
  end

  @impl true
  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    update_issue_state(issue_id, state_name, config_opts())
  end

  # ---------------------------------------------------------------------------
  # Injectable public API
  # ---------------------------------------------------------------------------

  @doc """
  Fetches issues from active board columns.

  Active states default to `["Todo", "In Progress"]` but can be overridden
  via the `:active_states` option.
  """
  @spec fetch_candidate_issues(keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues(opts) when is_list(opts) do
    active = Keyword.get(opts, :active_states, @default_active_states)
    fetch_and_filter(opts, &status_in?(&1, active))
  end

  @doc """
  Fetches issues whose board column matches any of the given `states`.
  """
  @spec fetch_issues_by_states([String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states, opts) when is_list(states) and is_list(opts) do
    fetch_and_filter(opts, &status_in?(&1, states))
  end

  @doc """
  Fetches issues whose node IDs are in the given list, regardless of column.
  """
  @spec fetch_issue_states_by_ids([String.t()], keyword()) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, opts) when is_list(issue_ids) and is_list(opts) do
    id_set = MapSet.new(issue_ids)

    fetch_and_filter(opts, fn {_status, content} ->
      MapSet.member?(id_set, content["id"])
    end)
  end

  @doc """
  Adds a comment to a GitHub issue via the `addComment` GraphQL mutation.
  """
  @spec create_comment(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_comment(issue_id, body, opts) when is_binary(issue_id) and is_binary(body) and is_list(opts) do
    graphql_fun = resolve_graphql_fun(opts)

    case graphql_fun.(@add_comment_mutation, %{"subjectId" => issue_id, "body" => body}) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Moves an issue to a different board column.

  TODO: Requires project item ID and field option ID lookups via the
  `updateProjectV2ItemFieldValue` mutation. Stubbed for now.
  """
  @spec update_issue_state(String.t(), String.t(), keyword()) :: {:error, :not_implemented}
  def update_issue_state(_issue_id, _state_name, _opts) do
    # TODO: Implement via updateProjectV2ItemFieldValue mutation.
    # This requires:
    #   1. Looking up the project item ID for the issue
    #   2. Looking up the field ID for the "Status" field
    #   3. Looking up the option ID for the target column name
    #   4. Calling the updateProjectV2ItemFieldValue mutation
    {:error, :not_implemented}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_and_filter(opts, filter_fn) do
    graphql_fun = resolve_graphql_fun(opts)
    owner = Keyword.fetch!(opts, :owner)
    repo = Keyword.fetch!(opts, :repo)
    project_number = Keyword.fetch!(opts, :project_number)

    case fetch_all_items(graphql_fun, owner, repo, project_number) do
      {:ok, raw_items} ->
        issues =
          raw_items
          |> Enum.filter(fn item ->
            content = item["content"]
            content != nil and content["__typename"] == "Issue"
          end)
          |> Enum.map(fn item ->
            status = get_in(item, ["fieldValueByName", "name"])
            content = item["content"]
            {status, content}
          end)
          |> Enum.filter(filter_fn)
          |> Enum.map(fn {status, content} ->
            Issue.normalize(content, status)
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, issues}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_items(graphql_fun, owner, repo, project_number) do
    fetch_all_items(graphql_fun, owner, repo, project_number, nil, [])
  end

  defp fetch_all_items(graphql_fun, owner, repo, project_number, cursor, acc) do
    variables = %{
      "owner" => owner,
      "repo" => repo,
      "projectNumber" => project_number,
      "first" => @page_size,
      "after" => cursor
    }

    case graphql_fun.(@project_items_query, variables) do
      {:ok, %{"data" => %{"repository" => %{"projectV2" => %{"items" => items}}}}} ->
        nodes = items["nodes"] || []
        page_info = items["pageInfo"] || %{}
        all = acc ++ nodes

        if page_info["hasNextPage"] do
          fetch_all_items(graphql_fun, owner, repo, project_number, page_info["endCursor"], all)
        else
          {:ok, all}
        end

      {:ok, unexpected} ->
        {:error, {:unexpected_response, unexpected}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp status_in?({status, _content}, states) do
    status in states
  end

  defp resolve_graphql_fun(opts) do
    Keyword.get_lazy(opts, :graphql_fun, fn ->
      fn query, variables -> Client.graphql(query, variables, opts) end
    end)
  end

  defp config_opts do
    config = Application.get_env(:symphony_elixir, :github, [])

    [
      owner: Keyword.get(config, :owner),
      repo: Keyword.get(config, :repo),
      project_number: Keyword.get(config, :project_number),
      active_states: Keyword.get(config, :active_states, @default_active_states)
    ]
  end
end
