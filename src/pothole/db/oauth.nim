# Copyright © penguinite 2024 <penguinite@tuta.io>
#
# This file is part of Pothole. Specifically, the Quark repository.
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
# quark/db/oauth.nim:
## This module contains all database logic for handling oauth tokens and code generation.
## Such as generating them, deleting them, verifying them and whatnot.

import quark/private/database
import quark/[auth_codes, apps, strextra]
import rng

# From somewhere in the standard library
import std/[times]

proc updateTimestampForOAuth*(db: DbConn, id: string) = 
  if not has(db.getRow(sql"SELECT id FROM oauth WHERE id = ?;", id)):
    return
  db.exec(sql"UPDATE oauth SET last_use = ? WHERE id = ?;", utc(now()).toDbString(), id)

proc purgeOldOauthTokens*(db: DbConn) =
  for row in db.getAllRows(sql"SELECT id,code,cid,last_use FROM oauth;"):
    if row[2] != "" and not db.authCodeExists(row[2]):
      db.exec(sql"DELETE FROM oauth WHERE id = ?;", row[1])
      continue

    if not db.clientExists(row[3]):
      db.exec(sql"DELETE FROM oauth WHERE id = ?;", row[1])
      continue

    if now().utc - toDateFromDb(row[4]) == initDuration(weeks = 1):
      db.exec(sql"DELETE FROM oauth WHERE id = ?;", row[1])

proc tokenExists*(db: DbConn, id: string): bool =
  db.updateTimestampForOAuth(id)
  return has(db.getRow(sql"SELECT id FROM oauth WHERE id = ?;", id))

proc tokenUsesCode*(db: DbConn, id: string): bool =
  return parseBool(db.getRow(sql"SELECT uses_code FROM oauth WHERE id = ?;", id)[0])

proc getTokenFromCode*(db: DbConn, code: string): string =
  return db.getRow(sql"SELECT id FROM oauth WHERE code = ?;", code)[0]

proc createToken*(db: DbConn, cid: string, code: string = ""): string =
  var id = randstr(32)

  while db.tokenExists(id):
    id = randstr(32)

  let uses_code = code != ""

  if db.getTokenFromCode(code) != "":

    return # Token already exist, we dont want a database error.

  db.exec(
    sql"INSERT INTO oauth VALUES (?,?,?,?,?);",
    id, uses_code, code, cid, utc(now()).toDbString()
  )

  return id


proc getTokenCode*(db: DbConn, id: string): string =
  return db.getRow(sql"SELECT code FROM oauth WHERE id = ?;", id)[0]

proc getTokenUser*(db: DbConn, id: string): string =
  return db.getUserFromAuthCode(db.getTokenCode(id))

proc getTokenApp*(db: DbConn, id: string): string =
  return db.getRow(sql"SELECT cid FROM oauth WHERE id = ?;", id)[0]

proc deleteOAuthToken*(db: DbConn, id: string) =
  if db.tokenUsesCode(id):
    db.deleteAuthCode(db.getTokenCode(id))
  db.exec(sql"DELETE FROM oauth WHERE id = ?;", id)

proc tokenMatchesClient*(db: DbConn, id, client_id: string): bool =
  return db.getRow(sql"SELECT cid FROM oauth WHERE id = ?;", id)[0] == client_id

  
