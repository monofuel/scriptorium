version     = "20.0.1"
author      = "Andrew Brower"
description = "Agent orchestration system for managing hierarchical AI coding agents."
license     = "MIT"

srcDir = "src"

bin = @["scriptorium"]

requires "nim >= 2.2.14"
requires "MCPort >= 1.2.0"
requires "ACPort >= 1.1.1"
requires "jsony >= 1.1.6"
requires "mummy >= 0.4.8"
requires "guildy >= 2.0.0"
requires "mosty >= 0.1.0"
