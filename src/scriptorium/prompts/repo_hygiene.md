## Repository hygiene

Do not commit log files, diagnostic output, build artifacts, test output,
replay data, binary files, or temporary data to the repository. These belong
in .gitignore or /tmp. When staging changes, prefer `git add <specific-files>`
over `git add -A` to avoid accidentally committing large or ephemeral files.
