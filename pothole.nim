# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
#
# This file is part of Pothole.
# 
# Pothole is free software: you can redistribute it and/or modify it under the terms of
# the GNU Affero General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
# 
# Pothole is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with Pothole. If not, see <https://www.gnu.org/licenses/>. 

# From somewhere in Quark
import quark/[database]

# From somewhere in Pothole
import pothole/[routes, lib, conf, database, assets]

# From standard library
import std/[tables]
from std/strutils import join

# From nimble
import mummy, mummy/routers

echo "Pothole version ", lib.version 
echo "Copyright © Leo Gavilieau 2022-2023." 
echo "Copyright © penguinite <penguinite@tuta.io> 2024." 
echo "Licensed under the GNU Affero General Public License version 3 or later" 

proc exit() {.noconv.} =
  error "Interrupted by Ctrl+C"
# Catch Ctrl+C so we can exit without causing a stacktrace
setControlCHook(exit)

echo "Using ", getConfigFilename(), " as config file"

let config = setup(getConfigFilename())
var port = 3500
if config.exists("web","port"):
  port = config.getInt("web","port")

if not hasDbHost(config):
  log "Couldn't retrieve database host. Using \"127.0.0.1:5432\" as default"
  log ""

if not hasDbName(config):
  log "Couldn't retrieve database name. Using \"pothole\" as default"

if not hasDbUser(config):
  log "Couldn't retrieve database user login. Using \"pothole\" as default"
  
if not hasDbPass(config):
  log "Couldn't find database user password from the config file or environment, did you configure pothole correctly?"
  error "Database user password couldn't be found."

log "Opening database at ", config.getDbHost()

# Initialize database
discard setup(
  config.getDbName(),
  config.getDbUser(),
  config.getDbHost(),
  config.getDbPass()
)

# Create directory for pure static files
discard initStatic(config)
discard initTemplates(config)

log "Serving on http://localhost:" & $port

var router: Router
for url in renderURLs.keys:
  router.get(url, serveAndRender)

newServer(router).serve(Port(port))