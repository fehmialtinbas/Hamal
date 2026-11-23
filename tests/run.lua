-- Run from the repository root:  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local T = require("harness")

require("spec_rules")
require("spec_commands")
require("spec_mailer")

os.exit(T.report() and 0 or 1)
