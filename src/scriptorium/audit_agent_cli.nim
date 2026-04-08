import
  ./audit_agent

proc runAudit*(repoPath: string) =
  ## Run the audit agent against the given repository path.
  let reportPath = runAuditAgent(repoPath)
  if reportPath.len > 0:
    echo reportPath
