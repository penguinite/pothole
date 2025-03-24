# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
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
# db/email_codes.nim:
## This module handles Email verification codes for users.
## This module does not handle sending email verification codes,
## there is a separate module `pothole/email.nim` to do this exact job.

# From Pothole
import private/utils, users, ../strextra

# From somewhere in the standard library
import std/times

# From elsewhere (third-party libraries)
import rng, db_connector/db_postgres

proc emailCodeExists*(db: DbConn, code: string): bool =
  has(db.getRow(sql"SELECT id FROM email_codes WHERE id = ?;", code))

proc emailCodeExistsForUser*(db: DbConn, user: string): bool =
  has(db.getRow(sql"SELECT id FROM email_codes WHERE uid = ?;", user))

proc getEmailCodeByUser*(db: DbConn, code: string): string =
  db.getRow(sql"SELECT uid FROM email_codes WHERE id = ?;", code)[0]

proc emailCodeValid*(db: DbConn, code, user: string): bool =
  db.emailCodeExists(code) and db.getEmailCodeByUser(code) == user

proc deleteEmailCode*(db: DbConn, code: string) =
  db.exec(sql"DELETE FROM email_codes WHERE id = ?;", code)

proc deleteEmailCodeByUser*(db: DbConn, user: string) =
  db.exec(sql"DELETE FROM email_codes WHERE uid = ?;", user)

proc createEmailCode*(db: DbConn, user: string): string =
  result = randstr(32)

  # Check if another code already exists for this user first.
  # And delete it.
  if has(db.getRow(sql"SELECT 0 FROM email_codes WHERE uid = ?;", user)):
    db.deleteEmailCodeByUser(user)

  db.exec(sql"INSERT INTO email_codes VALUES (?,?);", result, user)

proc cleanupCodes*(db: DbConn) =
  for row in db.getAllRows(sql"SELECT id,uid,date FROM email_codes;"):
    if now().utc - toDate(row[2]) == initDuration(days = 1):
      db.deleteEmailCode(row[0])
    if not db.userIdExists(row[1]) or row[1] == "null":
      db.deleteEmailCode(row[0])