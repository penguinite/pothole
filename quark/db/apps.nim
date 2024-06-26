# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
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
# quark/db/boosts.nim:
## This module contains all database logic for handling boosts.

import ../private/database
import rng

# From somewhere in the standard library
import std/tables

# Store each column like this: {"COLUMN_NAME":"COLUMN_TYPE"}
const appsCols*: OrderedTable[string, string] = {"id": "TEXT PRIMARY KEY NOT NULL",
"name": "TEXT NOT NULL", # ID of post that user boosted
"link": "TEXT NOT NULL" # ID of user that boosted post
}.toOrderedTable

# TODO: Finish this and test it

proc createClient*(db: DbConn, tmp_id, name: string, link: string = "") =
  var id = tmp_id
  while db.getRow(sql"SELECT name FROM apps WHERE id = ?;", id)[0] != "":
    id = randstr()
  db.exec(sql"INSERT INTO apps(id, name, link) VALUES (?,?,?);",id,name,link)

proc createClient*(db: DbConn, name: string, link: string = "") =
  db.createClient(randstr(), name, link)

proc getClientLink*(db: DbConn, id: string): string = 
  return db.getRow(sql"SELECT link FROM apps WHERE id = ?;", id)[0]

proc getClientName*(db: DbConn, id: string): string = 
  return db.getRow(sql"SELECT name FROM apps WHERE id = ?;", id)[0]

proc getClientIdWithName*(db: DbConn, name: string): string = 
  return db.getRow(sql"SELECT id FROM apps WHERE name = ?;", name)[0]

proc clientExists*(db: DbConn, id: string): bool = 
  return has(db.getRow(sql"SELECT id FROM apps WHERE id = ?;", id))
