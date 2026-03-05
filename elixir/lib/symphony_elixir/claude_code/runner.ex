defmodule SymphonyElixir.ClaudeCode.Runner do
  @moduledoc """
  Runs Claude Code CLI in isolated workspaces.

  Uses `System.cmd/3` with `bash -c` to ensure stdin is closed (via `< /dev/null`)
  and CLAUDE* environment variables are removed to prevent nested session detection.
  """

  require Logger

  @claude_env_prefixes ["CLAUDE"]

  @spec run(Path.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workspace, prompt, issue, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 3_600_000)
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    skip_permissions = Keyword.get(opts, :dangerously_skip_permissions, true)

    shell_cmd = build_shell_command(prompt, dangerously_skip_permissions: skip_permissions)

    case run_claude_process(workspace, shell_cmd, timeout_ms) do
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
  def run_continuation(workspace, _session_id, prompt, issue, opts \\ []) do
    # Each turn runs as a fresh session since claude --print doesn't support
    # resuming with our generated session IDs. The workspace state persists
    # between turns so Claude can continue from where it left off.
    run(workspace, prompt, issue, opts)
  end

  @spec build_command(String.t(), keyword()) :: [String.t()]
  def build_command(prompt, opts \\ []) do
    skip = Keyword.get(opts, :dangerously_skip_permissions, true)
    base = ["--print", "-p", prompt]
    if skip, do: base ++ ["--dangerously-skip-permissions"], else: base
  end

  @spec build_resume_command(String.t(), String.t()) :: [String.t()]
  def build_resume_command(session_id, prompt) do
    ["--print", "--resume", session_id, "-p", prompt, "--dangerously-skip-permissions"]
  end

  @spec generate_session_id() :: String.t()
  def generate_session_id do
    "claude-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp build_shell_command(prompt, opts) do
    args = build_command(prompt, opts)
    "claude #{Enum.map_join(args, " ", &shell_escape/1)} < /dev/null"
  end

  defp build_resume_shell_command(session_id, prompt) do
    args = build_resume_command(session_id, prompt)
    "claude #{Enum.map_join(args, " ", &shell_escape/1)} < /dev/null"
  end

  defp shell_escape(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  defp clean_env do
    for {k, _v} <- System.get_env(),
        Enum.any?(@claude_env_prefixes, &String.starts_with?(k, &1)),
        do: {k, nil}
  end

  defp run_claude_process(workspace, shell_cmd, timeout_ms) do
    task =
      Task.async(fn ->
        System.cmd("bash", ["-c", shell_cmd],
          cd: workspace,
          env: clean_env(),
          stderr_to_stdout: true
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, status}} ->
        {:error, {:exit_status, status, output}}

      nil ->
        {:error, :timeout}
    end
  end

  defp issue_context(%{id: id, identifier: identifier}), do: "issue_id=#{id} issue_identifier=#{identifier}"
  defp issue_context(_), do: "issue_id=unknown"

  defp default_on_message(_), do: :ok
end
