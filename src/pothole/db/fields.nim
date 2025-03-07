# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
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
# db/fields.nim:
## This module contains all database logic for handling profile fields.
## 
## This isn't in the user table because database arrays are hell,
## and I would rather create a new database table for this purpose than
## deal with parsing arrays from a column again.
## 
## Besides, more tables never hurt anyone. Right?
import private/utils, ../strextra
import std/[times]
import db_connector/db_postgres

proc getFields*(db: DbConn, user: string): seq[(string, string, bool, DateTime)] =
  ## Returns the profile fields of a specific user.
  ## The first string is the key, the second is the value and the boolean is the verification status.
  for row in db.getAllRows(sql"SELECT * FROM fields WHERE uid = ?;", user):
    result.add(
      (
        row[0],
        row[1],
        row[2] == "t",
        toDateFromDb(row[3])
      )
    )

proc fieldExists*(db: DbConn, user, key, value: string): bool =
  ## Checks if a field exists
  has(db.getRow(sql"SELECT 0 FROM fields WHERE uid = ? AND key = ? AND value = ?;", user, key, value))

proc insertField*(db: DbConn, user, key, value: string, verified: bool = false) =
  ## Inserts a profile field into the database
  
  # Only insert a field if this exact one doesn't exist already
  if not db.fieldExists(user, key, value):
    db.exec(sql"INSERT INTO fields VALUES (?, ?, ?, ?);", key, value, user, verified)

proc removeField*(db: DbConn, user, key, val: string) =
  ## Removes a profile field
  db.exec(sql"DELETE FROM fields WHERE uid = ? AND key = ? AND value = ?;", user, key, val)

proc verifyField*(db: DbConn, user, key, val: string, date: DateTime = now().utc) =
  ## Turns a regular field into a "verified" field
  
  # Only verify if a field exists in the first place
  if db.fieldExists(user, key, val):
    db.exec(sql"UPDATE fields SET verified = true, verified_at = ?, WHERE uid = ? AND key = ? AND value = ?;", toDbString(date), user, key, val)

proc unverifyField*(db: DbConn, user, key, val: string) =
  ## Turns a "verified" field into a regular field.
  
  # Only unverify if a field exists in the first place
  if db.fieldExists(user, key, val):
    db.exec(sql"UPDATE fields SET verified = false WHERE uid = ? AND key = ? AND value = ?;", user, key, val)