# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
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
# database.nim:
## Some small functions for working with the database. (Open connections, fetch env info and so on.)
## 
## Keep in mind, you will still need to import the actual database logic from the db/ folder

# From somewhere in the standard library
import std/os

# Third party libraries
import waterpark/postgres, db_connector/db_postgres, iniplus

## In the past, we used an archaic and sorta messed up system for making
## the tables, these have been replaced with a plain old SQL script that gets read
## at compile-time.
##
## Unlike Pleroma, Pothole's config is entirely stored in the config file.
## There is no way to configure Pothole from the database alone.
## So we do not need a tool to generate SQL for a specific instance.

proc setup*(name, user, host, password: string,schemaCheck: bool = true): DbConn =
  ## setup() is called whenever you want to initialize a database schema.
  ## It does not merely launch a database connection, it also makes sure that every table needed is there.
  result = open(host, user, password, name)
  result.exec(sql(staticRead("assets/setup.sql")))

proc purge*(db: DbConn) =
  ## Purges all of the data, tables and whatnot from the database.
  ## 
  ## Obviously a destructive procedure, don't run carelessly...
  db.exec(sql(staticRead("assets/purge.sql")))

proc getDbHost*(config: ConfigTable): string =
  if existsEnv("POTHOLE_DBHOST"):
    return getEnv("POTHOLE_DBHOST")
  return config.getStringOrDefault("db", "host", "127.0.0.1:5432")

proc getDbName*(config: ConfigTable): string =
  if existsEnv("POTHOLE_DBNAME"):
    return getEnv("POTHOLE_DBNAME")
  return config.getStringOrDefault("db", "name", "pothole")

proc getDbUser*(config: ConfigTable): string =
  if existsEnv("POTHOLE_DBUSER"):
    return getEnv("POTHOLE_DBUSER")
  return config.getStringOrDefault("db", "user", "pothole")

proc getDbPass*(config: ConfigTable): string =
  if existsEnv("POTHOLE_DBPASS"):
    return getEnv("POTHOLE_DBPASS")
  return config.getString("db", "pass")