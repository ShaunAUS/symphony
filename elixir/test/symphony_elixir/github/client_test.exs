defmodule SymphonyElixir.GitHub.ClientTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.GitHub.Client

  @test_token "ghp_test_token_123"

  describe "graphql/3" do
    test "sends correct payload and auth header" do
      query = "query { viewer { login } }"
      variables = %{first: 10}

      request_fun = fn url, opts ->
        assert url == "https://api.github.com/graphql"
        headers = Keyword.get(opts, :headers, [])
        json = Keyword.get(opts, :json)

        assert {"Authorization", "Bearer #{@test_token}"} in headers
        assert {"Content-Type", "application/json"} in headers
        assert json["query"] == query
        assert json["variables"] == variables

        {:ok, %Req.Response{status: 200, body: %{"data" => %{"viewer" => %{"login" => "test"}}}}}
      end

      assert {:ok, %{"data" => %{"viewer" => %{"login" => "test"}}}} =
               Client.graphql(query, variables, token: @test_token, request_fun: request_fun)
    end

    test "returns error on non-200 status" do
      query = "query { viewer { login } }"

      request_fun = fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: "Unauthorized"}}
      end

      assert {:error, {:github_api_status, 401}} =
               Client.graphql(query, %{}, token: @test_token, request_fun: request_fun)
    end

    test "returns error on request failure" do
      query = "query { viewer { login } }"

      request_fun = fn _url, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end

      assert {:error, {:github_api_request, _reason}} =
               Client.graphql(query, %{}, token: @test_token, request_fun: request_fun)
    end
  end

  describe "rest_get/2" do
    test "sends GET with auth header" do
      request_fun = fn url, opts ->
        assert url == "https://api.github.com/repos/owner/repo/issues"
        headers = Keyword.get(opts, :headers, [])
        method = Keyword.get(opts, :method, :get)

        assert method == :get
        assert {"Authorization", "Bearer #{@test_token}"} in headers
        assert {"Accept", "application/vnd.github+json"} in headers

        {:ok, %Req.Response{status: 200, body: [%{"id" => 1, "title" => "Issue 1"}]}}
      end

      assert {:ok, [%{"id" => 1, "title" => "Issue 1"}]} =
               Client.rest_get("/repos/owner/repo/issues",
                 token: @test_token,
                 request_fun: request_fun
               )
    end

    test "returns error on non-200 status" do
      request_fun = fn _url, _opts ->
        {:ok, %Req.Response{status: 404, body: %{"message" => "Not Found"}}}
      end

      assert {:error, {:github_api_status, 404}} =
               Client.rest_get("/repos/owner/repo/issues",
                 token: @test_token,
                 request_fun: request_fun
               )
    end
  end

  describe "rest_post/3" do
    test "sends POST with body and auth header" do
      post_body = %{"title" => "New issue", "body" => "Description"}

      request_fun = fn url, opts ->
        assert url == "https://api.github.com/repos/owner/repo/issues"
        headers = Keyword.get(opts, :headers, [])
        method = Keyword.get(opts, :method, :get)
        json = Keyword.get(opts, :json)

        assert method == :post
        assert {"Authorization", "Bearer #{@test_token}"} in headers
        assert {"Accept", "application/vnd.github+json"} in headers
        assert json == post_body

        {:ok, %Req.Response{status: 201, body: %{"id" => 42, "title" => "New issue"}}}
      end

      assert {:ok, %{"id" => 42, "title" => "New issue"}} =
               Client.rest_post("/repos/owner/repo/issues", post_body,
                 token: @test_token,
                 request_fun: request_fun
               )
    end

    test "returns error on non-2xx status" do
      request_fun = fn _url, _opts ->
        {:ok, %Req.Response{status: 422, body: %{"message" => "Validation Failed"}}}
      end

      assert {:error, {:github_api_status, 422}} =
               Client.rest_post("/repos/owner/repo/issues", %{},
                 token: @test_token,
                 request_fun: request_fun
               )
    end
  end
end
