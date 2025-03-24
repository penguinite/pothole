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
# db/auth_codes.nim:
## This module handles authorization code creation, cleanup and processing.
## Authorization codes refer to the ones generated via the OAuth process.
## This is usually typically used to authorize apps (such as third party clients)
## to do various things to your account (or the instance depending on the scopes)
# From Pothole
import private/utils, apps, users, ../strextra

# From somewhere in the standard library
import std/[strutils, times], db_connector/db_postgres

# From elsewhere (third-party libraries)
import rng

proc getSpecificAuthCode*(db: DbConn, user, client: string): string =
  db.getRow(sql"SELECT id FROM auth_codes WHERE uid = ? AND cid = ?;", user, client)[0]

proc authCodeExists*(db: DbConn, user, client: string): bool =
  has(db.getRow(sql"SELECT 0 FROM auth_codes WHERE uid = ? AND cid = ?;", user, client))

proc authCodeExists*(db: DbConn, id: string): bool =
  has(db.getRow(sql"SELECT 0 FROM auth_codes WHERE id = ?;", id))

proc createAuthCode*(db: DbConn, user, client: string, scopes: seq[string]): string =
  ## Creates an auth code for a user and returns it.
  result = randstr(32)
  db.exec(
    sql"INSERT INTO auth_codes VALUES (?,?,?,?);",
    result, user, client, !$(scopes)
  )

proc getCodeScopes*(db: DbConn, id: string): seq[string] =
  toStrSeq(db.getRow(sql"SELECT scopes FROM auth_codes WHERE id = ?;", id)[0])
  
proc codeHasScopes*(db: DbConn, id:string, scopes: seq[string]): bool =
  let appScopes = db.getCodeScopes(id)
  for scope in scopes:
    for codeScope in appScopes:
      if codeScope == scope or codeScope == scope.returnStartOrScope():
        result = true
        break

proc deleteAuthCode*(db: DbConn, id: string) =
  db.exec(sql"DELETE FROM auth_codes WHERE id = ?;", id)

proc getUserFromAuthCode*(db: DbConn, id: string): string =
  ## Returns user id associated with an auth code
  db.getRow(sql"SELECT uid FROM auth_codes WHERE id = ?;", id)[0]

proc getAppFromAuthCode*(db: DbConn, id: string): string =
  ## Returns app id associated with an auth code
  db.getRow(sql"SELECT cid FROM auth_codes WHERE id = ?;", id)[0]

proc getAuthCodeDate*(db: DbConn, id: string): DateTime =
  toDate(db.getRow(sql"SELECT date FROM auth_codes WHERE id = ?;", id)[0])

proc authCodeValid*(db: DbConn, id: string): bool =
  ## Checks if an auth code is actually valid and can be used.
  # Obviously check if the auth code exists first.
  if not db.authCodeExists(id):
    return false
  
  # Check if the associated app exists
  # If an auth code isn't assigned to any valid app then it's invalid
  if not db.clientExists(db.getAppFromAuthCode(id)):
    return false
  
  # Check if the associated user exists
  # If the auth token is associated to a non-existent user then it is invalid.
  if not db.userIdExists(db.getUserFromAuthCode(id)):
    return false

  # Check if the auth code is assigned to the "Null" user
  # No auth code should be assigned to null, but it might happen.
  if db.getUserFromAuthCode(id) == "null":
    return false

  # Check if the code is a day old.
  # if it is a day old, then it's invalid. (And should be deleted at some point)
  if now().utc - db.getAuthCodeDate(id) == initDuration(days = 1):
    return false

  # If all our checks succeed then it has to be a valid auth code.
  return true

proc cleanupCodes*(db: DbConn) =
  ## Purge any invalid authentication codes
  for row in db.getAllRows(sql"SELECT id,date FROM auth_codes;"):
    if not db.authCodeValid(row[0]):
      db.deleteAuthCode(row[0])