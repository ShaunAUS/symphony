---
tracker:
  kind: github
  repo: "my-org/my-spring-app"
  project_number: 1
  filter_labels:
    - bug
    - feature
  auto_label: symphony
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Closed
polling:
  interval_ms: 15000
workspace:
  root: ~/symphony-workspaces
hooks:
  after_create: |
    git clone git@github.com:my-org/my-spring-app.git .
    ./gradlew dependencies || mvn dependency:resolve || true
agent:
  kind: claude_code
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: claude --print --verbose
  approval_policy: never
---

You are working on GitHub issue `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the issue is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed work unless needed for new changes.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended automation session. Work autonomously end-to-end.
2. Create branch `{{ issue.branch_name }}` from `origin/main`.
3. Implement the fix or feature described in the issue.
4. This is a Java + Spring Boot project:
   - Run `./gradlew build` (or `mvn verify`) to compile and test.
   - Ensure all tests pass before committing.
5. Write clean, focused commits referencing the issue number.
6. Push the branch and create a PR:
   - `git push -u origin {{ issue.branch_name }}`
   - `gh pr create --title "{{ issue.title }}" --body "Closes {{ issue.identifier }}"`
7. Add label `symphony` to the PR.
8. Only stop early for true blockers (missing auth, permissions, secrets).

## Guardrails

- Work only in the provided workspace. Do not touch other paths.
- Do not modify issue body or description.
- Keep commits small and logical.
- If blocked, document the blocker clearly and stop.
