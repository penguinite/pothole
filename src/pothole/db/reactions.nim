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
# db/quark/reactions.nim:
## This module contains all database logic for handling reactions.
## Including creation, retrieval, fetching and whatnot.

# From somewhere in Quark
import quark/private/database

# From somewhere in the standard library
import std/tables

proc getReactions*(db: DbConn, id: string): Table[string, seq[string]] =
  ## Retrieves a Table of reactions for a post. Result consists of a table where the keys are the specific reaction and the value is a sequence of reactors.
  for row in db.getAllRows(sql"SELECT uid,reaction FROM reactions WHERE pid = ?;", id):
    result[row[1]].add(row[0])
  return result

proc getNumOfReactions*(db: DbConn, id: string): int =
  for row in db.getAllRows(sql"SELECT reaction FROM reactions WHERE pid = ?;", id):
    inc(result)
  return result

proc hasAnyReaction*(db: DbConn, pid, uid: string): bool =
  return has(db.getRow(sql"SELECT reaction FROM reactions WHERE pid = ? AND uid = ?;", pid, uid))

proc addReaction*(db: DbConn, pid,uid,reaction: string) =
  ## Adds an individual reaction
  # Check if a reaction already exists previous
  if db.hasAnyReaction(pid, uid):
    return

  db.exec(sql"INSERT INTO reactions VALUES (?,?,?);",pid,uid,reaction)

proc addBulkReactions*(db: DbConn, pid: string, table: Table[string, seq[string]]) =
  ## Adds an entire table of reactions to the database
  for reaction,list in table.pairs:
    for user in list:
      db.addReaction(pid, user, reaction)

proc removeReaction*(db: DbConn, pid,uid: string) =
  ## Removes a reactions from the database
  db.exec(sql"DELETE FROM reactions WHERE pid = ? AND uid = ?;",pid,uid)

proc hasReaction*(db: DbConn, pid,uid,reaction: string): bool =
  ## Checks if a post has a reaction. Everything must match.
  return has(db.getRow(sql"SELECT reaction FROM reactions WHERE pid = ? AND uid = ? AND reaction = ?;", pid, uid, reaction))
