defmodule SymphonyElixir.ClaudeCode.Runner do
  @moduledoc """
  Runs Claude Code CLI in isolated workspaces via Erlang Port.
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
        on_message.(%{event: :turn_completed, session_id: session_id, output: output})
        Logger.info("Claude Code completed for #{issue_context(issue)} session_id=#{session_id}")
        {:ok, %{result: :turn_completed, session_id: session_id, output: output}}

      {:error, reason} ->
        Logger.error("Claude Code failed for #{issue_context(issue)}: #{inspect(reason)}")
        on_message.(%{event: :turn_failed, reason: reason})
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
        Logger.info("Claude Code continuation completed for #{issue_context(issue)} session_id=#{session_id}")
        {:ok, %{result: :turn_completed, session_id: session_id, output: output}}

      {:error, reason} ->
        on_message.(%{event: :turn_failed, reason: reason})
        {:error, reason}
    end
  end

  @spec build_command(String.t(), keyword()) :: [String.t()]
  def build_command(prompt, opts \\ []) do
    skip = Keyword.get(opts, :dangerously_skip_permissions, true)
    base = ["--print", "--verbose", "-p", prompt]
    if skip, do: base ++ ["--dangerously-skip-permissions"], else: base
  end

  @spec build_resume_command(String.t(), String.t()) :: [String.t()]
  def build_resume_command(session_id, prompt) do
    ["--print", "--verbose", "--resume", session_id, "-p", prompt, "--dangerously-skip-permissions"]
  end

  @spec generate_session_id() :: String.t()
  def generate_session_id do
    "claude-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp run_claude_process(workspace, args, timeout_ms) do
    claude_executable = System.find_executable("claude")

    if is_nil(claude_executable) do
      {:error, :claude_not_found}
    else
      port = Port.open(
        {:spawn_executable, String.to_charlist(claude_executable)},
        [:binary, :exit_status, :stderr_to_stdout,
         args: Enum.map(args, &String.to_charlist/1),
         cd: String.to_charlist(workspace)]
      )
      collect_output(port, timeout_ms, [])
    end
  end

  defp collect_output(port, timeout_ms, acc) do
    receive do
      {^port, {:data, data}} -> collect_output(port, timeout_ms, [data | acc])
      {^port, {:exit_status, 0}} -> {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      {^port, {:exit_status, status}} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {:error, {:exit_status, status, output}}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp issue_context(%{id: id, identifier: identifier}), do: "issue_id=#{id} issue_identifier=#{identifier}"
  defp issue_context(_), do: "issue_id=unknown"

  defp default_on_message(_), do: :ok
end
