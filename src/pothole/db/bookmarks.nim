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
# quark/db/bookmarks.nim:
## This module contains all database logic for handling user bookmarks.
## Including creation, retrieval, checking, updating and deletion
import quark/private/database

proc bookmarkExists*(db: DbConn, user, post: string): bool =
  return has(db.getRow(sql"SELECT 0 FROM bookmarks WHERE uid = ? AND pid = ?;", user, post))

proc bookmarkPost*(db: DbConn, user, post: string) =
  if db.bookmarkExists(user, post):
    return
  db.exec(sql"INSERT INTO bookmarks VALUES (?,?);",post, user)

proc getBookmarks*(db: DbConn, user: string, limit = 20): seq[string] =
  for row in db.getAllRows(sql("SELECT pid FROM bookmarks WHERE uid = ? LIMIT " & $limit & ";"), user):
    result.add(row[0])
  return result

proc getAllBookmarks*(db: DbConn, user: string): seq[string] =
  for row in db.getAllRows(sql"SELECT pid FROM bookmarks WHERE uid = ?;", user):
    result.add(row[0])
  return result

proc unbookmarkPost*(db: DbConn, user, post: string) =
  db.exec(sql"DELETE FROM bookmarks WHERE uid = ? AND pid = ?;", user, post)