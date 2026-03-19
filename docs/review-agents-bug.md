# review agents bug

- review agents are running now but not getting the mcp tool properly
- I recall having a race condition issue with MCP for the coder and submit_pr
- should double check if the review agent still has a similar bug and why tests aren't catching it
- oh should make e2e tests better, assert review agent is not stalling
