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

  alias SymphonyElixir.{Config, GitHub.Client, GitHub.Issue}

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

  @project_field_query """
  query($owner: String!, $repo: String!, $projectNumber: Int!) {
    repository(owner: $owner, name: $repo) {
      projectV2(number: $projectNumber) {
        id
        field(name: "Status") {
          ... on ProjectV2SingleSelectField {
            id
            options { id name }
          }
        }
      }
    }
  }
  """

  @issue_project_items_query """
  query($nodeId: ID!) {
    node(id: $nodeId) {
      ... on Issue {
        projectItems(first: 10) {
          nodes {
            id
            project { id }
          }
        }
      }
    }
  }
  """

  @update_field_mutation """
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }) {
      projectV2Item { id }
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
    filter_labels = Keyword.get(opts, :filter_labels, [])
    active = Keyword.get(opts, :active_states, @default_active_states)

    filter_fn =
      if filter_labels == [] do
        &status_in?(&1, active)
      else
        fn {status, content} ->
          has_label = has_any_label?(content, filter_labels)
          not_terminal = !terminal_status?(status, Keyword.get(opts, :terminal_states, []))
          has_label and not_terminal
        end
      end

    fetch_and_filter(opts, filter_fn)
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
  Moves an issue to a different board column via the `updateProjectV2ItemFieldValue` mutation.
  """
  @spec update_issue_state(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name, opts) when is_binary(issue_id) and is_binary(state_name) and is_list(opts) do
    graphql_fun = resolve_graphql_fun(opts)
    owner = Keyword.fetch!(opts, :owner)
    repo = Keyword.fetch!(opts, :repo)
    project_number = Keyword.fetch!(opts, :project_number)

    with {:ok, project_id, field_id, option_id} <- find_field_option(graphql_fun, owner, repo, project_number, state_name),
         {:ok, item_id} <- find_project_item(graphql_fun, issue_id, project_id) do
      case graphql_fun.(@update_field_mutation, %{
        "projectId" => project_id,
        "itemId" => item_id,
        "fieldId" => field_id,
        "optionId" => option_id
      }) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
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

  defp has_any_label?(content, filter_labels) do
    issue_labels =
      case content do
        %{"labels" => %{"nodes" => nodes}} when is_list(nodes) ->
          Enum.map(nodes, &String.downcase(&1["name"] || ""))
        _ -> []
      end

    downcased_filters = Enum.map(filter_labels, &String.downcase/1)
    Enum.any?(issue_labels, &(&1 in downcased_filters))
  end

  defp terminal_status?(status, terminal_states) when is_binary(status) do
    normalized = String.downcase(String.trim(status))
    Enum.any?(terminal_states, &(String.downcase(String.trim(&1)) == normalized))
  end

  defp terminal_status?(_, _), do: false

  defp find_field_option(graphql_fun, owner, repo, project_number, target_state) do
    case graphql_fun.(@project_field_query, %{"owner" => owner, "repo" => repo, "projectNumber" => project_number}) do
      {:ok, %{"data" => %{"repository" => %{"projectV2" => project}}}} ->
        project_id = project["id"]
        field = project["field"]
        field_id = field["id"]
        options = field["options"] || []

        case Enum.find(options, fn o -> String.downcase(o["name"]) == String.downcase(target_state) end) do
          nil -> {:error, {:status_option_not_found, target_state}}
          option -> {:ok, project_id, field_id, option["id"]}
        end

      {:ok, unexpected} -> {:error, {:unexpected_response, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_project_item(graphql_fun, issue_node_id, project_id) do
    case graphql_fun.(@issue_project_items_query, %{"nodeId" => issue_node_id}) do
      {:ok, %{"data" => %{"node" => %{"projectItems" => %{"nodes" => items}}}}} ->
        case Enum.find(items, fn item -> item["project"]["id"] == project_id end) do
          nil -> {:error, :project_item_not_found}
          item -> {:ok, item["id"]}
        end

      {:ok, unexpected} -> {:error, {:unexpected_response, unexpected}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_graphql_fun(opts) do
    Keyword.get_lazy(opts, :graphql_fun, fn ->
      fn query, variables -> Client.graphql(query, variables, opts) end
    end)
  end

  defp config_opts do
    repo = Config.github_repo()
    {owner, repo_name} = parse_repo(repo)

    [
      owner: owner,
      repo: repo_name,
      project_number: Config.github_project_number(),
      active_states: Config.linear_active_states() || @default_active_states,
      terminal_states: Config.linear_terminal_states() || [],
      filter_labels: Config.github_filter_labels(),
      token: System.get_env("GITHUB_TOKEN")
    ]
  end

  defp parse_repo(nil), do: {nil, nil}
  defp parse_repo(repo) when is_binary(repo) do
    case String.split(repo, "/") do
      [owner, name] -> {owner, name}
      _ -> {nil, repo}
    end
  end
end
