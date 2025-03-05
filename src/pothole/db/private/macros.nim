# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
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
# quark/private/macros.nim:
## This module contains any macro useful enough to be shared across the entire Quark project.
import std/macros
import db_connector/db_postgres

macro get*(obj: object, fld: string): untyped =
  ## A procedure to get a field of an object using a string.
  ## Like so: user.get("local") == user.local
  newDotExpr(obj, newIdentNode(fld.strVal))

macro autoStmt*(db: DbConn, x: typed, table: static[string], o: object): untyped =
  ## A procedure to magically call db.exec with only a object.
  ## And to have every field escaped by the database layer itself
  ## 
  ## Use it like so:  DATABASE_CONNECTION.autoStmt(OBJECT_TYPE, TABLE_NAME, OBJECT)
  ## So, to insert a user: db.autoStmt(User, "users", user)
  let impl = getImpl(x)[2][2]

  # First, get all the fields of the object definition
  var fields: seq[string] = @[]
  for x in impl:
    fields.add(x[0][1].strVal)
  
  # Then, create the sql statement
  var a = "INSERT INTO " & table & "("
  for i in fields:
    a.add(i)
    a.add ", "
  a = a[0..^3]
  a.add ") VALUES ("
  for i in fields:
    a.add("?, ")
  a = a[0..^3]
  a.add ");"

  result = newNimNode(nnkCommand)

  # Oh right, db.exec needs a SqlQuery object...
  # Alright, make a NimNode that acts like sql(a)
  var j = newNimNode(nnkPrefix)
  j.add ident("sql")
  j.add newStrLitNode(a)

  result.add(
    newDotExpr(
      ident(db.strVal),
      bindSym("exec")
    ),
    j # Here we add the generated statement
  )

  # So, I am not sure if this is neccesary.
  # But I would like to add the string conversion myself just in case
  var n = newNimNode(nnkAccQuoted)
  n.add ident("$")

  # Btw, this was the hardest part to figure out...
  # yeah... I am so thankful for the random forum post that hinted at putting this section here.
  for i in fields:
    result.add newCall(
    n,
    newDotExpr(
      ident(o.strVal),
      ident(i)
    ))