defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  Thin GitHub API client for REST and GraphQL communication.
  """

  require Logger

  @graphql_url "https://api.github.com/graphql"
  @rest_base_url "https://api.github.com"

  @doc """
  Sends a GraphQL query to the GitHub API.

  Options:
    * `:token` - GitHub personal access token (falls back to `GITHUB_TOKEN` env var)
    * `:request_fun` - injectable request function for testing, `(url, opts) -> {:ok, response} | {:error, reason}`
  """
  @spec graphql(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables \\ %{}, opts \\ [])
      when is_binary(query) and is_map(variables) and is_list(opts) do
    token = resolve_token(opts)
    request_fun = Keyword.get(opts, :request_fun, &default_request/2)

    payload = %{"query" => query, "variables" => variables}

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case request_fun.(@graphql_url, headers: headers, json: payload) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status} = response} ->
        Logger.error(
          "GitHub GraphQL request failed status=#{status} body=#{summarize_body(response.body)}"
        )

        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub GraphQL request failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @doc """
  Sends a GET request to the GitHub REST API.

  `path` is appended to `https://api.github.com`.

  Options:
    * `:token` - GitHub personal access token (falls back to `GITHUB_TOKEN` env var)
    * `:request_fun` - injectable request function for testing
  """
  @spec rest_get(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def rest_get(path, opts \\ []) when is_binary(path) and is_list(opts) do
    token = resolve_token(opts)
    request_fun = Keyword.get(opts, :request_fun, &default_request/2)
    url = @rest_base_url <> path

    headers = rest_headers(token)

    case request_fun.(url, headers: headers, method: :get) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      {:ok, %{status: status} = response} ->
        Logger.error(
          "GitHub REST GET #{path} failed status=#{status} body=#{summarize_body(response.body)}"
        )

        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub REST GET #{path} failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  @doc """
  Sends a POST request to the GitHub REST API.

  `path` is appended to `https://api.github.com`.

  Options:
    * `:token` - GitHub personal access token (falls back to `GITHUB_TOKEN` env var)
    * `:request_fun` - injectable request function for testing
  """
  @spec rest_post(String.t(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def rest_post(path, body, opts \\ []) when is_binary(path) and is_list(opts) do
    token = resolve_token(opts)
    request_fun = Keyword.get(opts, :request_fun, &default_request/2)
    url = @rest_base_url <> path

    headers = rest_headers(token)

    case request_fun.(url, headers: headers, method: :post, json: body) do
      {:ok, %{status: status, body: resp_body}} when status >= 200 and status < 300 ->
        {:ok, resp_body}

      {:ok, %{status: status} = response} ->
        Logger.error(
          "GitHub REST POST #{path} failed status=#{status} body=#{summarize_body(response.body)}"
        )

        {:error, {:github_api_status, status}}

      {:error, reason} ->
        Logger.error("GitHub REST POST #{path} failed: #{inspect(reason)}")
        {:error, {:github_api_request, reason}}
    end
  end

  defp resolve_token(opts) do
    Keyword.get(opts, :token) || System.get_env("GITHUB_TOKEN")
  end

  defp rest_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/vnd.github+json"}
    ]
  end

  defp default_request(url, opts) do
    headers = Keyword.get(opts, :headers, [])
    method = Keyword.get(opts, :method, :post)

    req_opts = [
      headers: headers,
      connect_options: [timeout: 30_000]
    ]

    req_opts =
      case Keyword.get(opts, :json) do
        nil -> req_opts
        json -> Keyword.put(req_opts, :json, json)
      end

    case method do
      :get -> Req.get(url, req_opts)
      :post -> Req.post(url, req_opts)
    end
  end

  defp summarize_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(1_000)
    |> inspect()
  end

  defp summarize_body(body) do
    body
    |> inspect(limit: 20, printable_limit: 1_000)
    |> truncate(1_000)
  end

  defp truncate(str, max_bytes) when is_binary(str) do
    if byte_size(str) > max_bytes do
      binary_part(str, 0, max_bytes) <> "...<truncated>"
    else
      str
    end
  end
end
