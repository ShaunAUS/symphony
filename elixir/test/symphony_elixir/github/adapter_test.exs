defmodule SymphonyElixir.GitHub.AdapterTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Adapter
  alias SymphonyElixir.Linear.Issue

  @owner "test-owner"
  @repo "test-repo"
  @project_number 1

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp base_opts(graphql_fun) do
    [
      graphql_fun: graphql_fun,
      owner: @owner,
      repo: @repo,
      project_number: @project_number,
      active_states: ["Todo", "In Progress"]
    ]
  end

  defp project_item(status, issue_fields) do
    %{
      "fieldValueByName" => %{"name" => status},
      "content" => Map.merge(%{"__typename" => "Issue"}, issue_fields)
    }
  end

  defp page_info(has_next \\ false, cursor \\ nil) do
    %{"hasNextPage" => has_next, "endCursor" => cursor}
  end

  defp items_response(nodes, page_info) do
    {:ok,
     %{
       "data" => %{
         "repository" => %{
           "projectV2" => %{
             "items" => %{
               "nodes" => nodes,
               "pageInfo" => page_info
             }
           }
         }
       }
     }}
  end

  defp issue_map(id, number, title) do
    %{
      "id" => id,
      "number" => number,
      "title" => title,
      "body" => "Description for #{title}",
      "url" => "https://github.com/#{@owner}/#{@repo}/issues/#{number}",
      "labels" => %{"nodes" => [%{"name" => "bug"}]},
      "createdAt" => "2025-01-01T00:00:00Z",
      "updatedAt" => "2025-01-02T00:00:00Z"
    }
  end

  # ---------------------------------------------------------------------------
  # fetch_candidate_issues
  # ---------------------------------------------------------------------------

  describe "fetch_candidate_issues/1" do
    test "returns normalized issues from active columns" do
      graphql_fun = fn _query, variables ->
        assert variables["owner"] == @owner
        assert variables["repo"] == @repo
        assert variables["projectNumber"] == @project_number

        nodes = [
          project_item("Todo", issue_map("ID_1", 1, "First issue")),
          project_item("In Progress", issue_map("ID_2", 2, "Second issue"))
        ]

        items_response(nodes, page_info())
      end

      {:ok, issues} = Adapter.fetch_candidate_issues(base_opts(graphql_fun))

      assert length(issues) == 2
      assert [%Issue{id: "ID_1", state: "Todo"}, %Issue{id: "ID_2", state: "In Progress"}] = issues
    end

    test "filters out issues not in active states" do
      graphql_fun = fn _query, _variables ->
        nodes = [
          project_item("Todo", issue_map("ID_1", 1, "Active")),
          project_item("Done", issue_map("ID_2", 2, "Completed")),
          project_item("In Progress", issue_map("ID_3", 3, "Working"))
        ]

        items_response(nodes, page_info())
      end

      {:ok, issues} = Adapter.fetch_candidate_issues(base_opts(graphql_fun))

      assert length(issues) == 2
      ids = Enum.map(issues, & &1.id)
      assert "ID_1" in ids
      assert "ID_3" in ids
      refute "ID_2" in ids
    end

    test "handles pagination across multiple pages" do
      call_count = :counters.new(1, [:atomics])

      graphql_fun = fn _query, variables ->
        :counters.add(call_count, 1, 1)
        page = :counters.get(call_count, 1)

        case {page, variables["after"]} do
          {1, nil} ->
            nodes = [project_item("Todo", issue_map("ID_1", 1, "First"))]
            items_response(nodes, page_info(true, "cursor_1"))

          {2, "cursor_1"} ->
            nodes = [project_item("In Progress", issue_map("ID_2", 2, "Second"))]
            items_response(nodes, page_info())
        end
      end

      {:ok, issues} = Adapter.fetch_candidate_issues(base_opts(graphql_fun))

      assert length(issues) == 2
      assert :counters.get(call_count, 1) == 2
    end

    test "returns empty list when no matching issues" do
      graphql_fun = fn _query, _variables ->
        nodes = [
          project_item("Done", issue_map("ID_1", 1, "Finished")),
          project_item("Backlog", issue_map("ID_2", 2, "Queued"))
        ]

        items_response(nodes, page_info())
      end

      {:ok, issues} = Adapter.fetch_candidate_issues(base_opts(graphql_fun))

      assert issues == []
    end

    test "skips non-Issue content types (e.g. DraftIssue)" do
      graphql_fun = fn _query, _variables ->
        nodes = [
          project_item("Todo", issue_map("ID_1", 1, "Real issue")),
          %{
            "fieldValueByName" => %{"name" => "Todo"},
            "content" => %{"__typename" => "DraftIssue", "title" => "Draft"}
          }
        ]

        items_response(nodes, page_info())
      end

      {:ok, issues} = Adapter.fetch_candidate_issues(base_opts(graphql_fun))

      assert length(issues) == 1
      assert hd(issues).id == "ID_1"
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_issues_by_states
  # ---------------------------------------------------------------------------

  describe "fetch_issues_by_states/2" do
    test "returns issues matching requested states" do
      graphql_fun = fn _query, _variables ->
        nodes = [
          project_item("Todo", issue_map("ID_1", 1, "Todo issue")),
          project_item("In Progress", issue_map("ID_2", 2, "WIP")),
          project_item("Done", issue_map("ID_3", 3, "Done issue"))
        ]

        items_response(nodes, page_info())
      end

      opts = Keyword.put(base_opts(graphql_fun), :active_states, nil)
      {:ok, issues} = Adapter.fetch_issues_by_states(["Done"], opts)

      assert length(issues) == 1
      assert hd(issues).state == "Done"
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_issue_states_by_ids
  # ---------------------------------------------------------------------------

  describe "fetch_issue_states_by_ids/2" do
    test "returns only issues with matching IDs" do
      graphql_fun = fn _query, _variables ->
        nodes = [
          project_item("Todo", issue_map("ID_1", 1, "Issue 1")),
          project_item("In Progress", issue_map("ID_2", 2, "Issue 2")),
          project_item("Done", issue_map("ID_3", 3, "Issue 3"))
        ]

        items_response(nodes, page_info())
      end

      {:ok, issues} = Adapter.fetch_issue_states_by_ids(["ID_1", "ID_3"], base_opts(graphql_fun))

      assert length(issues) == 2
      ids = Enum.map(issues, & &1.id)
      assert "ID_1" in ids
      assert "ID_3" in ids
    end
  end

  # ---------------------------------------------------------------------------
  # create_comment
  # ---------------------------------------------------------------------------

  describe "create_comment/3" do
    test "delegates addComment mutation to graphql_fun" do
      graphql_fun = fn query, variables ->
        assert query =~ "addComment"
        assert variables["subjectId"] == "ISSUE_NODE_ID"
        assert variables["body"] == "Hello from Symphony"

        {:ok,
         %{
           "data" => %{
             "addComment" => %{
               "commentEdge" => %{"node" => %{"id" => "COMMENT_1"}}
             }
           }
         }}
      end

      assert :ok = Adapter.create_comment("ISSUE_NODE_ID", "Hello from Symphony", base_opts(graphql_fun))
    end

    test "returns error when graphql_fun fails" do
      graphql_fun = fn _query, _variables ->
        {:error, :network_error}
      end

      assert {:error, :network_error} =
               Adapter.create_comment("ID", "body", base_opts(graphql_fun))
    end
  end

  # ---------------------------------------------------------------------------
  # update_issue_state
  # ---------------------------------------------------------------------------

  describe "update_issue_state/3" do
    test "returns {:error, :not_implemented} stub" do
      graphql_fun = fn _query, _variables -> {:ok, %{}} end

      assert {:error, :not_implemented} =
               Adapter.update_issue_state("ID_1", "Done", base_opts(graphql_fun))
    end
  end
end
