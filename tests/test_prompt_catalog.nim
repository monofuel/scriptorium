## Unit tests for centralized prompt template rendering.

import
  std/[strutils, unittest],
  scriptorium/prompt_catalog

suite "prompt catalog":
  test "renderPromptTemplate replaces all bound placeholders":
    let rendered = renderPromptTemplate(
      "alpha {{ONE}} beta {{TWO}} gamma\n",
      [
        (name: "ONE", value: "first"),
        (name: "TWO", value: "second"),
      ],
    )

    check rendered == "alpha first beta second gamma\n"

  test "renderPromptTemplate fails when requested placeholder is absent":
    expect ValueError:
      discard renderPromptTemplate(
        "alpha {{ONE}} beta\n",
        [
          (name: "TWO", value: "second"),
        ],
      )

  test "renderPromptTemplate fails when template keeps unresolved placeholders":
    expect ValueError:
      discard renderPromptTemplate(
        "alpha {{ONE}} beta {{TWO}}\n",
        [
          (name: "ONE", value: "first"),
        ],
      )

  test "template constants include expected placeholder markers":
    check CodingAgentTemplate.contains("{{TICKET_PATH}}")
    check CodingAgentTemplate.contains("{{PROJECT_REPO_PATH}}")
    check CodingAgentTemplate.contains("{{WORKTREE_PATH}}")
    check CodingAgentTemplate.contains("submit_pr")
    check CodingAgentTemplate.contains("verify that the `submit_pr` MCP tool")
    check ArchitectAreasTemplate.contains("{{CURRENT_SPEC}}")
    check ArchitectAreasTemplate.contains("{{PROJECT_REPO_PATH}}")
    check ArchitectAreasTemplate.contains("{{WORKTREE_PATH}}")
    check ManagerTicketsTemplate.contains("{{AREA_CONTENT}}")
    check ManagerTicketsTemplate.contains("{{PROJECT_REPO_PATH}}")
    check PlanScopeTemplate.contains("{{PROJECT_REPO_PATH}}")
    check PlanScopeTemplate.contains("{{WORKTREE_PATH}}")
    check ArchitectPlanOneShotTemplate.contains("{{USER_REQUEST}}")
    check ArchitectPlanInteractiveTemplate.contains("{{USER_MESSAGE}}")
    check ReviewAgentTemplate.contains("submit_review")
    check ReviewAgentTemplate.contains("verify that the `submit_review` MCP tool")
    check CodexRetryContinuationTemplate.contains("{{TIMEOUT_KIND}}")
    check CodexRetryDefaultContinuationText.contains("Continue from the previous attempt")
    check CodexRetryDefaultContinuationText.contains("submit_pr")

  test "agents example template contains expanded library catalog":
    check AgentsExampleTemplate.contains("nimby")
    check AgentsExampleTemplate.contains("jsony")
    check AgentsExampleTemplate.contains("mummy")
    check AgentsExampleTemplate.contains("curly")
    check AgentsExampleTemplate.contains("debby")
    check AgentsExampleTemplate.contains("pixie")

  test "architect and manager prompts contain dependency guidance":
    check ArchitectAreasTemplate.contains("Dependency guidance")
    check ArchitectPlanOneShotTemplate.contains("Dependency guidance")
    check ArchitectPlanInteractiveTemplate.contains("Dependency guidance")
    check ManagerTicketsTemplate.contains("Dependency guidance")

