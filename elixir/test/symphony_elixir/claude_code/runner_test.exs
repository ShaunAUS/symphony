defmodule SymphonyElixir.ClaudeCode.RunnerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ClaudeCode.Runner

  test "build_command/2 produces correct CLI args with skip permissions" do
    args = Runner.build_command("Fix the bug", dangerously_skip_permissions: true)
    assert "--print" in args
    assert "-p" in args
    assert "--dangerously-skip-permissions" in args
    assert "Fix the bug" in args
  end

  test "build_command/2 without skip permissions" do
    args = Runner.build_command("Fix bug", dangerously_skip_permissions: false)
    assert "--print" in args
    refute "--dangerously-skip-permissions" in args
  end

  test "build_resume_command/2 includes resume flag and session id" do
    args = Runner.build_resume_command("session-abc", "Continue")
    assert "--resume" in args
    assert "session-abc" in args
    assert "--print" in args
    assert "-p" in args
    assert "Continue" in args
  end

  test "generate_session_id/0 returns unique string" do
    id1 = Runner.generate_session_id()
    id2 = Runner.generate_session_id()
    assert is_binary(id1)
    assert String.starts_with?(id1, "claude-")
    assert id1 != id2
  end
end
