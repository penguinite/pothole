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
# quark/db/apps.nim:
## This module handles apps, it provides functions for creating them,
## deleting them, modifying them or retrieving them.
## Apps are a fundamental part of the Mastodon API and they need support
## at the database level.
import private/utils, ../strextra

# From somewhere in the standard library
import std/[strutils, times]

# From elsewhere (third-party libraries)
import rng

## APIDIFF: (API Difference)
## Apps in Pothole are handled different than by Mastodon.
## 
## In any version newer than v4.3, apps *CANNOT* be automatically deleted or purged at all
## In any version older than v4.3, apps *CAN* be deleted *UNLESS* an app requests a token, in which case, it is immortal.
## 
## Pothole on startup however deletes any app that was last used a week ago, to prevent the accumulation of dead apps that use up space.
## Apps are considered "temporary data" , meaning they can be deleted at any point if they are not used frequently.
## Other examples of "temporary data" are:
## - auth codes: These aren't deleted depending on the date they were last used but whether or not they are valid. See authCodeValid() in auth_codes.nim
## - email codes: Deleted if the code is a day old and if they are assigned to the "null" user. (See cleanupCodes() in email_codes.nim)
## 

proc purgeOldApps*(db: DbConn) =
  for row in db.getAllRows(sql"SELECT id, last_accessed FROM apps;"):
    if row[0] == "0": # Skip "null" app.
      continue

    if now().utc - toDateFromDb(row[1]) == initDuration(weeks = 1):
      db.exec(sql"DELETE FROM apps WHERE id = ?;", row[0])
      db.exec(sql"DELETE FROM auth_codes WHERE cid = ?;", row[0])
      db.exec(sql"DELETE FROM oauth WHERE cid = ?;", row[0])

proc updateTimestamp*(db: DbConn, id: string) =
  db.exec(sql"UPDATE apps SET last_accessed = ? WHERE id = ?;", utc(now()).toDbString(), id)

proc createNullClient*(db: DbConn) =
  db.exec(sql"INSERT INTO apps VALUES (?,?,?,?,?,?,?);", "0", "0", "read", "", "", "", utc(now()).toDbString())

proc createClient*(db: DbConn, name: string, link: string = "", scopes: string = "read", redirect_uri: string = "urn:ietf:wg:oauth:2.0:oob"): string =
  var id, secret = randstr()
  
  # Check if ID already exists first.
  while db.getRow(sql"SELECT name FROM apps WHERE id = ?;", id)[0] != "":
    id = randstr()

  # Check if secret already exists.
  while db.getRow(sql"SELECT name FROM apps WHERE secret = ?;", secret)[0] != "":
    secret = randstr()

  db.exec(sql"INSERT INTO apps VALUES (?,?,?,?,?,?,?);", id, secret, scopes, redirect_uri, name, link, utc(now()).toDbString())
  return id

proc getClientLink*(db: DbConn, id: string): string = 
  return db.getRow(sql"SELECT link FROM apps WHERE id = ?;", id)[0]

proc getClientName*(db: DbConn, id: string): string = 
  return db.getRow(sql"SELECT name FROM apps WHERE id = ?;", id)[0]

proc getClientSecret*(db: DbConn, id: string): string =
  return db.getRow(sql"SELECT secret FROM apps WHERE id = ?;", id)[0]

proc getClientScopes*(db: DbConn, id: string): seq[string] =
  return db.getRow(sql"SELECT scopes FROM apps WHERE id = ?;", id)[0].split(" ")

proc getClientRedirectUri*(db: DbConn, id: string): string =
  return db.getRow(sql"SELECT redirect_uri FROM apps WHERE id = ?;", id)[0]

proc clientExists*(db: DbConn, id: string): bool = 
  if has(db.getRow(sql"SELECT id FROM apps WHERE id = ?;", id)):
    db.updateTimestamp(id)
    return true
  else:
    return false

proc returnStartOrScope*(s: string): string =
  if s.startsWith("read"):
    return "read"
  if s.startsWith("write"):
    return "write"
  if s.startsWith("admin:read"):
    return "admin:read"
  if s.startsWith("admin:write"):
    return "admin:write"
  return s

proc hasScope*(db: DbConn, id:string, scope: string): bool =
  let appScopes = db.getRow(sql"SELECT scopes FROM apps WHERE id = ?;", id)[0].split(" ")
  result = false

  for appScope in appScopes:
    if appScope == scope or appScope == scope.returnStartOrScope():
      result = true
      break
  
  return result

proc hasScopes*(db: DbConn, id:string, scopes: seq[string]): bool =
  let appScopes = db.getRow(sql"SELECT scopes FROM apps WHERE id = ?;", id)[0].split(" ")
  result = false

  for scope in scopes:
    for appScope in appScopes:
      if appScope == scope or appScope == scope.returnStartOrScope():
        result = true
        break
  
  return result

proc verifyScope*(pre_scope: string): bool =
  ## Just verifies if a scope is valid or not.
  if len(pre_scope) < 4 or len(pre_scope) > 34:
    # "read" is the smallest possible scope, so anything less is invalid automatically.
    # "admin:write:canonical_email_blocks" is the largest possible scope, so anything larger is invalid automatically.
    return false

  var scope = pre_scope.toLowerAscii()

  # If there is no colon, then it means
  # it's one of the simpler scopes.
  if ':' notin scope:
    case scope:
    of "read", "write", "push", "profile", "follow": # Yes, follow is a deprecated scope... But that doesn't stop apps from using it! :D
      return true
    else:
      return false
  
  # Let's get this out of the way
  # Since the later code does not deal with
  # admin:read and admin:write
  case scope:
  of "admin:read", "admin:write":
    return true
  else:
    discard
  
  var list = scope.split(":")
  if len(list) < 2 or len(list) > 3:
    return false # A scope has usually 2-3 parts of colons. Anything higher is unusual.

  # Parse the first part.
  case list[0]:
  of "read", "write":
    if len(list) != 2:
      return false # A read scope only has 2 parts.
    return list[1] in @["accounts", "blocks", "bookmarks", "favorites", "favourites", "filters", "follows", "lists", "mutes", "notifications", "search", "statuses"]
  of "admin":
    if len(list) != 3:
      return false # An admin scope only has 3 parts.
    
    case list[1]:
    of "read", "write":
      return list[2] in @["accounts", "reports", "domain_allows", "domain_blocks", "ip_blocks", "email_domain_blocks", "canonical_domain_blocks"]
    else:
      return false
  else:
    return false

proc humanizeScope*(pre_scope: string): string =
  ## When given a scope, it returns a string containing a human explanation for what it does.
  ## This is used in the OAuth authorization page (among other places)
  let scope = pre_scope.toLowerAscii()
  case scope:
  of "read": return "Full read access for everything except admin actions."
  of "write": return "Full write access for everything except admin actions."
  of "profile": return "Read access to account metadata"
  of "push": return "Access to the Web Push API."
  of "admin:write": return "Full write access for everything admin-related."
  of "admin:read": return "Full read access for everything admin-related."
  of "follow": return "Full read and write access to user blocks, mutes and followers/following."
  else:
    discard

  if scope.startsWith("write"):
    result = "Full write access for "
  
  if scope.startsWith("read"):
    result = "Full read access for "
  
  if scope.startsWith("admin:write"):
    result = "Full administrator write access for "
  
  if scope.startsWith("admin:read"):
    result = "Full administrator read access for "

  let scopeList = scope.split(':')
  case scopeList[0]:
  of "read", "write":
    case scopeList[1]:
    of "accounts": return result & "account details."
    of "blocks": return result & "user blocks."
    of "bookmarks": return result & "user bookmarks."
    of "conversations": return result & "direct user conversations."
    of "favourites", "write:favorites": return result & "user favorites."
    of "filters": return result & "user filters."
    of "follows": return result & "list of followers and following."
    of "lists": return result & "other user lists."
    of "media": return result & "media attachments."
    of "mutes": return result & "user mutes."
    of "notifications": return result & "notification and notification settings."
    of "reports": return result & "reports."
    of "statuses": return result & "posts."
    else:
      return "Unknown scope."
  of "admin":
    if scopeList.len() != 2:
      return "Unknown admin scope."

    case scopeList[2]:
    of "accounts": return result & "user accounts and account details."
    of "reports": return result & "reports against users, posts and instances."
    of "domain_allows": return result & "domain allows"
    of "domain_blocks": return result & "domain blocks"
    of "ip_blocks": return result & "IP address blocks"
    of "email_domain_blocks": return result & "email provider blocks"
    of "canonical_email_blocks": return result & "email blocks"
    else:
      return "Unknown admin scope."
  else:
    return "Unknown scope."