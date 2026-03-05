---
tracker:
  kind: github
  repo: "ShaunAUS/symphony"
  project_number: 10
  filter_labels:
    - bug
    - feature
  active_states:
    - Ready
    - In progress
  terminal_states:
    - Done
    - Closed
polling:
  interval_ms: 15000
workspace:
  root: /tmp/symphony_workspaces
hooks:
  after_create: |
    git clone https://github.com/ShaunAUS/symphony.git .
agent:
  kind: claude_code
  max_concurrent_agents: 2
  max_turns: 5
server:
  port: 4000
codex:
  command: claude --print
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
   - Look at Java source code in src/main/java/
   - Keep changes minimal and focused
5. Commit convention (AngularJS style):
   - Format: `<type>({{ issue.identifier }}): <description>`
   - Types: `feat` (new feature), `fix` (bug fix), `refactor`, `test`, `docs`, `chore`
   - One logical change per commit, keep commits as small as possible
   - Group related changes into one commit (e.g. entity + repository + service for same domain)
   - Examples:
     - `feat({{ issue.identifier }}): add Member entity with JPA mapping`
     - `feat({{ issue.identifier }}): add MemberRepository and MemberService`
     - `fix({{ issue.identifier }}): handle null email in UserService`
6. Push the branch and create a PR:
   - `git push -u origin {{ issue.branch_name }}`
   - `gh pr create --title "{{ issue.title }}" --body "Closes {{ issue.identifier }}"`
7. Only stop early for true blockers (missing auth, permissions, secrets).

## Guardrails

- Work only in the provided workspace. Do not touch other paths.
- Do not modify issue body or description.
- Keep commits small and logical.
- If blocked, document the blocker clearly and stop.
