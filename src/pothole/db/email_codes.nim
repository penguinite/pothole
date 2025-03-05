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
# quark/db/email_codes.nim:
## This module handles Email verification codes for users.
## It does not handle sending them, Pothole, the server program has
## a module for sending emails, pothole/email

# From Quark
import quark/private/database
import quark/[users, strextra]

# From somewhere in the standard library
import std/[times]

# From elsewhere (third-party libraries)
import rng

proc emailCodeExists*(db: DbConn, code: string): bool =
  return has(db.getRow(sql"SELECT id FROM email_codes WHERE id = ?;", code))

proc emailCodeExistsForUser*(db: DbConn, user: string): bool =
  return has(db.getRow(sql"SELECT id FROM email_codes WHERE uid = ?;", user))

proc getEmailCodeByUser*(db: DbConn, code: string): string =
  return db.getRow(sql"SELECT uid FROM email_codes WHERE id = ?;", code)[0]

proc emailCodeValid*(db: DbConn, code, user: string): bool =
  return db.emailCodeExists(code) and db.getEmailCodeByUser(code) == user

proc deleteEmailCode*(db: DbConn, code: string) =
  db.exec(sql"DELETE FROM email_codes WHERE id = ?;", code)

proc deleteEmailCodeByUser*(db: DbConn, user: string) =
  db.exec(sql"DELETE FROM email_codes WHERE uid = ?;", user)

proc createEmailCode*(db: DbConn, user: string): string =
  var id = randstr(32)
  
  # Check if another code already exists for this user first.
  let testRow = db.getRow(sql"SELECT id FROM email_codes WHERE uid = ?;", user)
  if has(testRow):
    while db.emailCodeExists(id):
      id = randstr(32)
    
    # Delete the previous code.
    # To avoid DB errors.
    # And also for security reasons.
    db.deleteEmailCode(testRow[0])

  db.exec(sql"INSERT INTO email_codes VALUES (?,?,?);", id, user, utc(now()).toDbString())
  return id

proc cleanupCodes*(db: DbConn) =
  for row in db.getAllRows(sql"SELECT id,uid,date FROM email_codes;"):
    if now().utc - toDateFromDb(row[2]) == initDuration(days = 1):
      db.deleteEmailCode(row[0])
    
    if not db.userIdExists(row[1]) or row[1] == "null":
      db.deleteEmailCode(row[0])