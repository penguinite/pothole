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
# quark/db/boosts.nim:
## This module contains all database logic for handling boosts.
## A "boost" is used to promote posts, putting them on a user's profile
## and thus visible to a user's followers.
## 
## There are kinds of boosts, hence why we store an extra "level" column
## Someone might want to show a post to only their followers and no where else.
## Quote-boosts are not considered true boosts. They're just posts with a link.

import quark/private/database, quark/[users, shared, strextra]

# From somewhere in the standard library
import std/tables

proc getBoosts*(db: DbConn, id: string): Table[PostPrivacyLevel, seq[string]] =
  ## Retrieves a Table of boosts for a post.
  ## Result consists of a table where the keys are the specific levels and the value is a sequence of boosters associated with this level.
  for row in db.getAllRows(sql"SELECT uid,level FROM boosts WHERE pid = ?;", id):
    result[toPrivacyLevelFromDb(row[1])].add(row[0])
  return result

proc getBoostsQuick*(db: DbConn, id: string): seq[string] =
  ## Returns a list of boosters for a specific post
  for row in db.getAllRows(sql"SELECT uid,level FROM boosts WHERE pid = ?;", id):
    result.add(row[0])
  return result

proc isBoostable*(db: DbConn, uid, pid: string): bool =
  ## Checks if the post can be boosted.
  ##
  ## Currently, this only checks if the post you're trying to boost
  ## is either a public or unlisted post.
  ## TODO: This might be wrong.
  let level = toPrivacyLevelFromDb(db.getRow(sql"SELECT level FROM posts WHERE id = ?;", pid)[0])
  return level == Public or level == Unlisted

proc getBoostsQuickWithHandle*(db: DbConn, id: string): seq[string] =
  ## Returns a list of boosters for a specific post, used when rendering /users/USER.
  ## This is the exact same thing as above but we call the db to convert the ids into handles.
  for id in db.getBoostsQuick(id):
    result.add(db.getHandleFromId(id))
  return result

proc hasAnyBoost*(db: DbConn, pid,uid: string): bool =
  ## Checks if a post has a boost. The specific level doesn't matter tho
  return has(db.getRow(sql"SELECT 0 FROM boosts WHERE pid = ? AND uid = ?;", pid, uid))

proc removeBoost*(db: DbConn, pid,uid: string) =
  ## Removes a boost from the database
  db.exec(sql"DELETE FROM boosts WHERE pid = ? AND uid = ?;",pid,uid)

proc hasBoost*(db: DbConn, pid,uid: string, level: PostPrivacyLevel): bool =
  ## Checks if a post has a boost. Everything must match.
  return has(db.getRow(sql"SELECT level FROM boosts WHERE pid = ? AND uid = ? AND level = ?;", pid, uid, toDbString(level)))

proc addBoost*(db: DbConn, pid,uid: string, level: PostPrivacyLevel) =
  ## Adds an individual boost
  # Check if a boost already exists before
  if db.hasAnyBoost(pid, uid):
    return

  # Filter out invalid levels.
  # You can't have a boost limited to some unknown people
  # and a "private boost" (that is just a bookmark lol)
  if level in {Limited, Private}:
    return
  
  db.exec(sql"INSERT INTO boosts (pid, uid, level) VALUES (?,?,?);",pid,uid,toDbString(level))

proc getNumOfBoosts*(db: DbConn, pid: string): int =
  for i in db.getAllRows(sql"SELECT 0 FROM boosts WHERE pid = ?;", pid):
    inc(result)
  return result