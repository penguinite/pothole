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
import std/strutils, db_connector/db_postgres

# From elsewhere (third-party libraries)
import rng

proc getSpecificAuthCode*(db: DbConn, user, client: string): string =
  ## Returns a specific auth code.
  db.getRow(sql"SELECT id FROM auth_codes WHERE uid = ? AND cid = ?;", user, client)[0]

proc authCodeExists*(db: DbConn, user, client: string): bool =
  has(db.getRow(sql"SELECT id FROM auth_codes WHERE uid = ? AND cid = ?;", user, client))

proc authCodeExists*(db: DbConn, id: string): bool =
  has(db.getRow(sql"SELECT id FROM auth_codes WHERE id = ?;", id))

proc createAuthCode*(db: DbConn, user, client, scopes: seq[string]): string =
  ## Creates a code
  if db.authCodeExists(user, client):
    raise newException(DbError, "Code already exists for user \"" & user & "\" and client \"" & client & "\"")

  result = randstr(32)
  while db.authCodeExists(result):
    result = randstr(32)
  
  db.exec(sql"INSERT INTO auth_codes VALUES (?,?,?,?);", result, user, client, toDbString(scopes))
  return result

proc codeHasScopes*(db: DbConn, id:string, scopes: seq[string]): bool =
  let appScopes = split(db.getRow(sql"SELECT scopes FROM auth_codes WHERE id = ?;", id)[0], ',')
  result = false

  for scope in scopes:
    for codeScope in appScopes:
      if codeScope == scope or codeScope == scope.returnStartOrScope():
        result = true
        break
  
  return result

proc getScopesFromCode*(db: DbConn, id: string): seq[string] =
  split(db.getRow(sql"SELECT scopes FROM auth_codes WHERE id = ?;", id)[0], ',')

proc deleteAuthCode*(db: DbConn, id: string) =
  ## Deletes an authentication code
  db.exec(sql"""
DELETE FROM oauth WHERE code = ?;
DELETE FROM auth_codes WHERE id = ?;
""", id, id)

proc getUserFromAuthCode*(db: DbConn, id: string): string =
  ## Returns user id when given auth code
  db.getRow(sql"SELECT uid FROM auth_codes WHERE id = ?;", id)[0]

proc getAppFromAuthCode*(db: DbConn, id: string): string =
  db.getRow(sql"SELECT cid FROM auth_codes WHERE id = ?;", id)[0]

proc authCodeValid*(db: DbConn, id: string): bool =
  ## Does some extra checks in addition to authCodeExists()
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

  # If all our checks succeed then it has to be a valid auth code.
  return true

proc cleanupCodes*(db: DbConn) =
  ## Purge any codes that are invalid.
  for row in db.getAllRows(sql"SELECT id FROM auth_codes;"):
    if not db.authCodeValid(row[0]):
      db.deleteAuthCode(row[0])

proc cleanupCodesVerbose*(db: DbConn): seq[(string, string, string)] =
  ## Same as cleanupCodes but it returns a list of all of the codes that were deleted.
  ## Useful for interactive situations such as in potholectl.
  ## The sequences consists of a tulip in the order: Auth Code Id -> User Id -> Client Id
  for row in db.getAllRows(sql"SELECT id,uid,cid FROM auth_codes;"):
    if not db.authCodeValid(row[0]):
      result.add((row[0], row[1], row[2]))
  return result

proc getCodesForUser*(db: DbConn, user_id: string): seq[string] =
  ## Returns all the valid authentication codes associated with a user
  var purge = db.userIdExists(user_id)
  if user_id == "null":
    purge = true
    
  for row in db.getAllRows(sql"SELECT id FROM auth_codes WHERE uid = ?;", user_id):
    if not db.clientExists(db.getAppFromAuthCode(row[0])) or purge:
      db.deleteAuthCode(row[0])
      continue
    result.add row[0]
  return result