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
#
# quark/private/database.nim:
## This module contains all the common procedures used across the entire database.
# From somewhere in the standard library
import std/strutils except isEmptyOrWhitespace, parseBool

# From somewhere else (nimble etc.)
import db_connector/db_postgres
export db_postgres

proc createDbTable*(db: DbConn, tablename: string, cols: seq[string]) =
  ## We use this procedure to create a SQL statement that creates a table using the hard-coded rules
  # We build the sql statement slowly.
  var sqlStatement = "CREATE TABLE IF NOT EXISTS " & tablename & " ("
  sqlStatement.add(cols.join(", "))
  sqlStatement.add(");") # Add final two characters

  # Now we run and hope for the best!
  db.exec(sql(sqlStatement))

proc update*(db: DbConn, table, condition, column, value: string): bool =
  ## A procedure to update any value, in any column in any table.
  ## This procedure should be wrapped, you can use updateUserByHandle() or
  ## updateUserById() instead of using this directly.
  var sqlStatement = "UPDATE " & table & " SET " & column & " = " & value & " WHERE " & condition & ";"
  try:
    db.exec(sql(sqlStatement))
    return true
  except:
    return false

proc matchTableSchema*(db: DbConn, tablename: string, table: seq[string]) =
  ## We use this procedure to compare two tables against each other and see if there are any mismatches.
  ## A mismatch could signify someone forgetting to complete the migration instructions.
  #var cols: seq[string] = @[] # To store the columns that are currently in the database
  #var missing: seq[string] = @[] # To store the columns missing from the database.
  # TODO: Implement this

proc has*(row: Row): bool =
  ## A quick helper function to check if a Row is valid.
  return len(row) != 0 and row[0] != ""