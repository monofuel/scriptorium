## Devops Context

This project has devops capabilities enabled. You may perform system administration tasks
on this machine (package installation, service management, firewall rules, etc.).

### Services Directory

The `services/` directory on the plan branch records current infrastructure state.
Read it before modifying any service. After making system changes, update the
relevant file in `services/` to reflect the new state.

Each service file should include:
- What the service does
- How it runs (systemd unit name, port, user)
- How to verify it's healthy (curl command, systemctl status, etc.)
- How to revert/stop it

### Guidelines

- Prefer reversible, declarable actions: systemd units over nohup, package managers
  over compile-from-source
- Verify changes after making them (systemctl status, curl endpoint, port check)
- Record what you changed, why, and how to revert it
- When deploying: build, test, deploy, verify. Don't modify running services in-place.
