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
import private/utils, ../[strextra, shared]
import std/[times]
import db_connector/db_postgres

proc getFields*(db: DbConn, user: string): seq[ProfileField] =
  ## Returns the profile fields of a specific user.
  for row in db.getAllRows(sql"SELECT key,val,verified,verified_at FROM fields WHERE uid = ?;", user):
    result.add(
      ProfileField(
        key: row[0],
        val: row[1],
        verified: row[2] == "t",
        verified_at: row[3].toDate()
      )
    )

proc fieldExists*(db: DbConn, user, key, value: string): bool =
  ## Checks if a field exists
  has(db.getRow(sql"SELECT 0 FROM fields WHERE uid = ? AND key = ? AND value = ?;", user, key, value))

proc insertField*(db: DbConn, user, key, value: string) =
  ## Inserts a profile field into the database
  db.exec(sql"INSERT INTO fields (uid, key, val) VALUES (?,?,?);", user, key, value)

proc removeField*(db: DbConn, user, key, value: string) =
  ## Removes a profile field
  db.exec(sql"DELETE FROM fields WHERE uid = ? AND key = ? AND value = ?;", user, key, value)

proc verifyField*(db: DbConn, user, key, value: string, date: DateTime = now().utc) =
  ## Turns a regular field into a "verified" field
  
  # Only verify if a field exists in the first place
  db.exec(sql"UPDATE fields SET verified = true, verified_at = ?, WHERE uid = ? AND key = ? AND value = ?;", !$(date), user, key, value)

proc unverifyField*(db: DbConn, user, key, value: string) =
  ## Turns a "verified" field into a regular field.
  
  # Only unverify if a field exists in the first place
  db.exec(sql"UPDATE fields SET verified = false WHERE uid = ? AND key = ? AND value = ?;", user, key, value)