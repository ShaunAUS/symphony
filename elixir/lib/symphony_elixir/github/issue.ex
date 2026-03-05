defmodule SymphonyElixir.GitHub.Issue do
  @moduledoc """
  Normalizes GitHub API issue responses into `SymphonyElixir.Linear.Issue` structs
  so the orchestrator can treat GitHub and Linear issues uniformly.
  """

  alias SymphonyElixir.Linear.Issue

  @doc """
  Converts a GitHub issue map and a column name into a `Linear.Issue` struct.

  Supports both GraphQL (Projects V2 content) and REST API field formats.
  Returns `nil` for non-map input.
  """
  @spec normalize(term(), String.t()) :: Issue.t() | nil
  def normalize(issue, column_name) when is_map(issue) do
    number = issue["number"]

    %Issue{
      id: issue["id"] || issue["node_id"],
      identifier: "##{number}",
      title: issue["title"],
      description: issue["body"],
      priority: nil,
      state: column_name,
      branch_name: "symphony/#{number}",
      url: issue["url"] || issue["html_url"],
      assignee_id: nil,
      blocked_by: [],
      labels: extract_labels(issue),
      assigned_to_worker: true,
      created_at: parse_datetime(issue["createdAt"] || issue["created_at"]),
      updated_at: parse_datetime(issue["updatedAt"] || issue["updated_at"])
    }
  end

  def normalize(_invalid, _column_name), do: nil

  # GraphQL format: %{"labels" => %{"nodes" => [%{"name" => "bug"}]}}
  defp extract_labels(%{"labels" => %{"nodes" => labels}}) when is_list(labels) do
    labels
    |> Enum.map(& &1["name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  # REST format: %{"labels" => [%{"name" => "bug"}]}
  defp extract_labels(%{"labels" => labels}) when is_list(labels) do
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
