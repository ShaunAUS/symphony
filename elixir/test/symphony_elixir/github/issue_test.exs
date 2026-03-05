defmodule SymphonyElixir.GitHub.IssueTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Issue, as: GitHubIssue
  alias SymphonyElixir.Linear.Issue

  @valid_github_issue %{
    "node_id" => "I_kwDOABCDEF12345",
    "number" => 42,
    "title" => "Fix login bug",
    "body" => "Users cannot log in when using SSO.",
    "html_url" => "https://github.com/acme/repo/issues/42",
    "user" => %{"id" => 12345, "login" => "octocat"},
    "labels" => [
      %{"name" => "Bug"},
      %{"name" => "HIGH-PRIORITY"}
    ],
    "created_at" => "2026-03-01T10:00:00Z",
    "updated_at" => "2026-03-02T15:30:00Z"
  }

  describe "normalize/2" do
    test "converts a full GitHub issue to a Linear.Issue struct" do
      result = GitHubIssue.normalize(@valid_github_issue, "In Progress")

      assert %Issue{} = result
      assert result.id == "I_kwDOABCDEF12345"
      assert result.identifier == "#42"
      assert result.title == "Fix login bug"
      assert result.description == "Users cannot log in when using SSO."
      assert result.state == "In Progress"
      assert result.branch_name == "symphony/42"
      assert result.url == "https://github.com/acme/repo/issues/42"
      assert result.labels == ["bug", "high-priority"]
      assert result.assignee_id == nil
      assert result.priority == nil
      assert result.blocked_by == []
      assert result.assigned_to_worker == true
      assert result.created_at == ~U[2026-03-01 10:00:00Z]
      assert result.updated_at == ~U[2026-03-02 15:30:00Z]
    end

    test "handles nil body gracefully" do
      issue = Map.put(@valid_github_issue, "body", nil)
      result = GitHubIssue.normalize(issue, "Todo")

      assert %Issue{} = result
      assert result.description == nil
      assert result.title == "Fix login bug"
      assert result.state == "Todo"
    end

    test "returns nil for invalid input" do
      assert GitHubIssue.normalize(nil, "Todo") == nil
      assert GitHubIssue.normalize("not a map", "Todo") == nil
      assert GitHubIssue.normalize(123, "Todo") == nil
    end

    test "handles empty labels list" do
      issue = Map.put(@valid_github_issue, "labels", [])
      result = GitHubIssue.normalize(issue, "Done")

      assert %Issue{} = result
      assert result.labels == []
    end

    test "handles missing labels key" do
      issue = Map.delete(@valid_github_issue, "labels")
      result = GitHubIssue.normalize(issue, "Done")

      assert %Issue{} = result
      assert result.labels == []
    end

    test "handles malformed datetime strings" do
      issue =
        @valid_github_issue
        |> Map.put("created_at", "not-a-date")
        |> Map.put("updated_at", "also-bad")

      result = GitHubIssue.normalize(issue, "Todo")

      assert %Issue{} = result
      assert result.created_at == nil
      assert result.updated_at == nil
    end

    test "handles missing datetime fields" do
      issue =
        @valid_github_issue
        |> Map.delete("created_at")
        |> Map.delete("updated_at")

      result = GitHubIssue.normalize(issue, "Todo")

      assert %Issue{} = result
      assert result.created_at == nil
      assert result.updated_at == nil
    end

    test "handles GraphQL format (Projects V2 content)" do
      graphql_issue = %{
        "id" => "I_graphql_id",
        "number" => 99,
        "title" => "GraphQL issue",
        "body" => "From Projects V2",
        "url" => "https://github.com/acme/repo/issues/99",
        "labels" => %{"nodes" => [%{"name" => "Feature"}]},
        "createdAt" => "2026-03-01T10:00:00Z",
        "updatedAt" => "2026-03-02T15:30:00Z"
      }

      result = GitHubIssue.normalize(graphql_issue, "Todo")

      assert %Issue{} = result
      assert result.id == "I_graphql_id"
      assert result.identifier == "#99"
      assert result.branch_name == "symphony/99"
      assert result.labels == ["feature"]
      assert result.created_at == ~U[2026-03-01 10:00:00Z]
    end
  end
end
