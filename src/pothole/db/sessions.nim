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
# quark/db/sessions.nim:
## This module contains all database logic for handling user sessions.
## Such as verifying them, creating them and also deleting them
## if the user demands it or if they have gone out-of-date.

import quark/[users, strextra]
import quark/private/database
import rng

# From somewhere in the standard library
import std/[times]

proc updateTimestampForSession*(db: DbConn, id: string) = 
  if not has(db.getRow(sql"SELECT id FROM sessions WHERE id = ?;", id)):
    return
  db.exec(sql"UPDATE sessions SET last_used = ? WHERE id = ?;", utc(now()).toDbString(), id)

proc sessionExists*(db: DbConn, id: string): bool =
  ## Checks if a session exists and returns whether or not it does.
  db.updateTimestampForSession(id)
  return has(db.getRow(sql"SELECT uid FROM sessions WHERE id = ?;", id))

proc createSession*(db: DbConn, user: string, date: DateTime = now().utc): string =
  ## Creates a session for a user and returns it's id
  ## The user parameter should contain a user's id.
  var id = randstr(22)
  while db.sessionExists(id):
    id = randstr(22)
  
  db.exec(
    sql"INSERT INTO sessions VALUES (?, ?, ?);",
    id,
    user,
    toDbString(date)
  )
  return id

proc getSessionUser*(db: DbConn, id: string): string =
  ## Retrieves the user id associated with a session.
  ## The id parameter should contain the session id.
  return db.getRow(sql"SELECT uid FROM sessions WHERE id = ?;", id)[0]

proc getSessionUserHandle*(db: DbConn, id: string): string =
  ## Retrieves the user handle associated with a session.
  ## The id parameter should contain the session id.
  return db.getHandleFromId(db.getSessionUser(id))

proc getSessionDate*(db: DbConn, id: string): DateTime =
  ## Retrieves the last use date associated with a session.
  ## The id parameter should contain the session id.
  return toDateFromDb(
    db.getRow(sql"SELECT last_used FROM sessions WHERE id = ?;", id)[0]
  )

proc sessionExpired*(db: DbConn, id: string): bool =
  ## Checks if a session has expired, meaning that it is 1 week old.
  if not db.sessionExists(id):
    return true
  return now().utc - db.getSessionDate(id) == initDuration(weeks = 1)

proc sessionValid*(db: DbConn, id: string): bool =
  ## Checks if a session is valid.
  ## The id parameter should contain the session id,
  ## The user parameter should contain the user's id.
  ## 
  ## Slightly different from `sessionExpired()`, since 
  ## `sessionExpired()` does not check if the users match
  if not db.sessionExists(id):
    return false

  if db.sessionExpired(id):
    return false

  return true

proc deleteSession*(db: DbConn, id: string) =
  ## Deletes a session.
  db.exec(sql"DELETE FROM sessions WHERE id = ?;", id)

proc deleteAllSessionsForUser*(db: DbConn, user: string) =
  ## Deletes all the sessions that a single user has.
  db.exec(sql"DELETE FROM sessions WHERE uid = ?;", user)

proc cleanSessions*(db: DbConn) =
  ## Cleans sessions that have expired or that belong to non-existent users.
  for row in db.getAllRows(sql"SELECT id,uid FROM sessions;"):
    if not db.userIdExists(row[1]) or db.sessionExpired(row[0]):
      db.deleteSession(row[0])

proc cleanSessionsVerbose*(db: DbConn): seq[(string, string)] =
  ## Cleans sessions that have expired.
  ## This function is verbose as in, it returns the exact sessions that it deleted.
  ## So you can log them.
  ## 
  ## The output is a sequence containing tulips where each element is the following:
  ## 1. ID: The ID of the session
  ## 2. User: The ID of the user that the session belonged to
  for row in db.getAllRows(sql"SELECT id FROM sessions;"):
    if db.sessionExpired(row[0]):
      result.add((
        row[0],
        db.getSessionUser(row[0])
      ))
      db.deleteSession(row[0])

proc getTotalSessions*(db: DbConn): int =
  result = 0
  for row in db.getAllRows(sql"SELECT id FROM sessions;"):
    inc(result)
  return result

proc getTotalValidSessions*(db: DbConn): int =
  result = 0
  for row in db.getAllRows(sql"SELECT id FROM sessions;"):
    if not db.sessionExpired(row[0]):
      inc result
  return result 
