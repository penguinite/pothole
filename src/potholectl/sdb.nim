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
#
# potholectl/sdb.nim:
## Database operations for Potholectl
## This simply parses the subsystem & command (and maybe arguments)
## and it calls the appropriate function from src/db.nim

# From somewhere in Potholectl
import shared

# From somewhere in Quark
import quark/[db, strextra, auth_codes, sessions, oauth, apps, users]

# From somewhere in Pothole
import pothole/[database, lib, conf]

# From standard libraries
from std/os import execShellCmd
from std/strutils import split, `%`, splitLines

# From elsewhere
import rng

proc db_check*(config = "pothole.conf"): int =
  ## This command initializes a database with schema checking enabled,
  ## you can use it to test if the database needs migration.
  let cnf = conf.setup(config)
  log "Re-running database initialization with schema checking enabled."
  discard setup(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
    true
  )
  return 0

proc db_purge*(config = "pothole.conf"): int =
  ## This command purges the entire database, it removes all tables and all the data within them.
  ## It's quite obvious but this command will erase any data you have, so be careful.
  let cnf = conf.setup(config)
  log "Cleaning everything in database"
  init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  ).cleanDb()
  return 0

proc db_docker*(config = "pothole.conf", name = "potholeDb", allow_weak_password = false, expose_externally = false, ipv6 = false): int =
  ## This command creates a postgres docker container that automatically works with pothole.
  ## It reads the configuration file and takes note of the database configuration.
  ## And then it pulls the alpine:postgres docker image, and starts it up with the correct port, name, password anything.
  ## 
  ## If this command detects that you are using the default password ("SOMETHING_SECRET") then it will change it to an autogenerated 64 char length password for security's sake.
  ## In most cases, this behavior is perfectly acceptable and fine. But you can disable it with the -a or --allow-weak-password option.
  let cnf = conf.setup(config)
  log "Setting up postgres docker container according to config file"
  var
    # Sick one liner to figure out the port we need to expose.
    port = split(getDbHost(cnf), ":")[high(split(getDbHost(cnf), ":"))]
    password = cnf.getDbPass()
    dbname = cnf.getDbName()
    user = cnf.getDbUser()
    host = ""

  if port.isEmptyOrWhitespace():
    port = "5432"
    
  if not expose_externally:
    if ipv6: host.add("::1:")
    else: host.add("127.0.0.1:")
  host.add(port & ":5432")
    
  if password == "SOMETHING_SECRET" and not allow_weak_password:
    log "Changing weak database password to something more secure"
    password = randstr(64)
    echo "Please update the config file to reflect the following changes:"
    echo "[db] password is now \"", password, "\""
  
  log "Pulling docker container"
  discard exec "docker pull postgres:alpine"
  log "Creating the container itself"
  let id = exec "docker run --name $# -d -p $# -e POSTGRES_USER=$# -e POSTGRES_PASSWORD=$# -e POSTGRES_DB=$# postgres:alpine" % [name, host, user, password, dbname]
  if id == "":
    error "Please investigate the above errors before trying again."
  return 0

proc db_psql*(config = "pothole.conf"): int = 
  ## This command opens a psql shell in the database container.
  ## This is useful for debugging operations and generally figuring out where we went wrong. (in life)
  ## 
  ## Note: This command only works with the database container created by the db_docker cmd.
  let
    cnf = conf.setup(config)
    cmd = "docker exec -it potholeDb psql -U " & cnf.getDbUser() & " " & cnf.getDbName()
  echo "Executing: ", cmd
  discard execShellCmd cmd

proc db_run*(file: string, config = "pothole.conf"): int =
  ## Run any SQL-containing file on your Pothole database!
  ## 
  ## Note: Due to technical limitations, the file **HAS** to have each query/command on a single line!
  ## Seriously, if you forget this, you're gonna have an awful time! I am not joking!!!
  ## 
  ## Also, PLEASE BE SANE! DON'T RUN ANYTHING THAT YOU DIDN'T DOUBLE CHECK!
  let cnf = conf.setup(config)
  let db = init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  )

  for line in readFile(file).splitLines:
    echo "Running: ", line
    db.exec(sql(line))


proc db_clean*(config = "pothole.conf"): int =
  ## This command runs some cleanup procedures.
  let cnf = conf.setup(config)
  let db = init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  )
  log "Cleaning up sessions"
  for session in db.cleanSessionsVerbose():
    log "Cleaned up session belonging to \"", db.getHandleFromId(session[1]), "\""
  log "Cleaning up authentication codes"
  for code in db.cleanupCodesVerbose():
    log "Cleaned up auth code belonging to \"", db.getHandleFromId(code[1]), "\""
  log "Purging old apps/clients"
  db.purgeOldApps()
  log "Purging old oauth tokens"
  db.purgeOldOauthTokens()