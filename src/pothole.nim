# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
# Copyright © penguinite 2024 <penguinite@tuta.io>
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
import pothole/[shared, conf, routes, database, web]

# From standard library
import std/[strutils, os]

# From third-parties
import mummy, mummy/routers, iniplus

log "Pothole version ", phVersion
log "Copyright © Leo Gavilieau <xmoo@privacyrequired.com> 2022-2023"
log "Copyright © penguinite <penguinite@tuta.io> 2024-2025"
log "Licensed under the GNU Affero General Public License version 3 or later"

when not defined(useMalloc):
  {.warning: "Pothole is suspectible to a memory leak, which, for now, can only be fixed by supplying the -d:useMalloc compile-time option".}
  {.warning: "Your build does not supply -d:useMalloc, therefore it is susceptible to a memory leak".}
  log "This build of pothole was built without -d:useMalloc, and is thus suspectible to a memory leak"

proc exit() {.noconv.} =
  error "Interrupted by Ctrl+C"
# Catch Ctrl+C so we can exit our way.
setControlCHook(exit)

log "Using ", getConfigFilename(), " as config file"

let config = parseFile(getConfigFilename())

var port = 3500
if config.exists("web","port"):
  port = config.getInt("web","port")

# Provide useful hints on when default values are used...
# Erroring out if a password for the database does not exist.

if not (config.exists("db","host") or existsEnv("POTHOLE_DBHOST")):
  log "Couldn't retrieve database host. Using \"127.0.0.1:5432\" as default"

if not (config.exists("db","name") or existsEnv("POTHOLE_DBNAME")):
  log "Couldn't retrieve database name. Using \"pothole\" as default"

if not (config.exists("db","user") or existsEnv("POTHOLE_DBUSER")):
  log "Couldn't retrieve database user login. Using \"pothole\" as default"
  
if not (config.exists("db","password") or existsEnv("POTHOLE_DBPASS")):
  log "Couldn't find database user password from the config file or environment, did you configure pothole correctly?"
  error "Database user password couldn't be found."

log "Opening database at ", config.getDbHost()

# Initialize database
try:
  discard setup(
    config.getDbName(),
    config.getDbUser(),
    config.getDbHost(),
    config.getDbPass()
  )
except CatchableError as err:
  error "Couldn't initalize the database: ", err.msg

var router: Router

# Add API & web routes
for route in mummyRoutes:
  router.addRoute(route[1], route[0], route[2])
  router.addRoute(route[1], route[0] & "/", route[2]) # Trailing slash fix.
router.get("/", serveHome)

log "Serving on http://localhost:" & $port
initEverythingForRoutes()
newServer(router).serve(Port(port))