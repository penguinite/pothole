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

# From somewhere in Pothole
import pothole/[database, conf]
import pothole/db/[strextra, apps, oauth, auth_codes]

# From the standard library
import std/[mimetypes, os, macros, tables, json]
import std/strutils except isEmptyOrWhitespace, parseBool

# From elsewhere
import waterpark/postgres, db_connector/db_postgres, mummy, mummy/multipart
export postgres

const mimedb*: MimeDB = newMimetypes()

var
  configPool*: ConfigPool
  dbPool*: PostgresPool

proc realURL*(config: ConfigTable): string =
  return "http://" & config.getString("instance", "uri") & config.getStringOrDefault("web", "endpoint", "/")

proc initEverythingForRoutes*() =
  var size = 75
  if existsEnv("POTHOLE_CONFIG_SIZE"):
    size = parseInt(getEnv("POTHOLE_CONFIG_SIZE"))
  configPool = newConfigPool(size)

  configPool.withConnection config:
    dbPool = newPostgresPool(
      config.getIntOrDefault("db", "pool_size", 10),
      config.getdbHost(),
      config.getdbUser(),
      config.getdbPass(),
      config.getdbName()
    )

proc createHeaders*(a: string): HttpHeaders =
  result["Content-Type"] = a
  return

macro respJsonError*(msg: string, code = 400, headers = createHeaders("application/json")) =
  var req = ident"req"

  result = quote do:
    `req`.respond(
      `code`, `headers`, $(%*{"error": `msg`})
    )
    return

macro respJson*(msg: string, code = 200, headers = createHeaders("application/json")) =
  var req = ident"req"

  result = quote do:
    `req`.respond(
      `code`, `headers`, `msg`
    )
    return

proc queryParamExists*(req: Request, query: string): bool =
  ## Check if a query parameter (such as "?query=parameter") is valid and not empty
  return not req.queryParams[query].isEmptyOrWhitespace()

proc pathParamExists*(req: Request, path: string): bool =
  ## Checks if a path parameter such as /users/{user} is valid and not empty
  return not req.pathParams[path].isEmptyOrWhitespace()

type
  MultipartEntries* = Table[string, string]
  FormEntries* = Table[string, string]

proc unrollMultipart*(req: Request): MultipartEntries =
  ## Unrolls a Mummy multipart data thing into a table of strings.
  ## which is way easier to handle.
  ## TODO: Maybe reconsider this approach? The example file mentions a way to do this *without* copying.
  for entry in req.decodeMultipart():
    if entry.data.isNone():
      continue
    
    let
      (start, last) = entry.data.get()
      val = req.body[start .. last]

    if val.isEmptyOrWhitespace():
      continue

    result[entry.name] = val
  return result

proc multipartParamExists*(mp: MultipartEntries, param: string): bool =
  ## Returns a parameter submitted via a HTML form
  return mp.hasKey(param) and not mp[param].isEmptyOrWhitespace()

proc unrollForm*(req: Request): FormEntries =
  let entries = req.body.smartSplit('&')

  for entry in entries:
    if '=' notin entry:
      continue # Invalid entry: Does not have equal sign.

    let entrySplit = entry.smartSplit('=') # let's just re-use this amazing function.

    if len(entrySplit) != 2:
      continue # Invalid entry: Does not have precisely two parts.

    var
      key = entrySplit[0].decodeQueryComponent()
      val = entrySplit[1].decodeQueryComponent()

    if key.isEmptyOrWhitespace() or val.isEmptyOrWhitespace():
      continue # Invalid entry: Key or val (or both) are empty or whitespace. Invalid.

    result[key] = val
  
  return result

proc formParamExists*(fe: FormEntries, param: string): bool =
  ## Returns a parameter submitted via a HTML form
  return fe.hasKey(param) and not fe[param].isEmptyOrWhitespace()


proc hasSessionCookie*(req: Request): bool =
  ## Checks if the request has a Session cookie for authorization.
  
  # The cookie header might contain other cookies.
  # So we need to parse this header.
  # The header looks like so: Name=Value; Name=Value
  if not req.headers.contains("Cookie"):
    return false

  var
    val = ""
    flag = false
  for item in req.headers["Cookie"].smartSplit('='):
    case flag:
    of false:
      if item == "session":
        flag = true
        continue
    of true:
      val = item
      break
  
  return not (val.isEmptyOrWhitespace() and val != "null")

proc hasValidStrKey*(j: JsonNode, k: string): bool =
  ## Checks if a key in a json node object is a valid string.
  ## It primarily checks for existence, kind, and emptyness.
  try: return j.hasKey(k) and j[k].kind == JString and not j[k].getStr().isEmptyOrWhitespace()
  except: return false


proc fetchSessionCookie*(req: Request): string = 
  ## Fetches the session cookie (if it exists) from a request.
  var flag = false
  for val in req.headers["Cookie"].smartSplit('='):
    if flag:
      return val
    if val == "session":  
      flag = true

proc getContentType*(req: Request): string =
  ## Returns the content-type of a request.
  ## 
  ## This also does some extra checks for if the content-type
  ## has other info (like MIME boundary info) and strips it out
  result = "application/x-www-form-urlencoded"
  if req.headers.contains("Content-Type"):
    result = req.headers["Content-Type"]
  
  # Some clients such as tuba send their content-type as
  # multipart/form-data; boundary=...
  # And so, we will return everything before
  # the first semicolon 
  if ';' in result:
    result = result.split(';')[0]

proc authHeaderExists*(req: Request): bool =
  ## Checks if the auth header exists, which is required for some API routes.
  return req.headers.contains("Authorization") and not isEmptyOrWhitespace(req.headers["Authorization"])

proc getAuthHeader*(req: Request): string =
  ## Gets the auth from a request header if it exists
  let split = req.headers["Authorization"].split("Bearer")

  if len(split) > 1: return split[high(split)].cleanString()
  else: return split[0].cleanString()

proc verifyAccess*(req: Request, db: DbConn, scope: string) =
  ## A simple helper proc for verifying access to API routes.
  ## 
  ## Heres how to use verifyAccess to ensure a client
  ## is authenticated with the scope "read:statuses"
  runnableExamples:
    try:
      req.verifyAccess(db, "read:statuses")
    except CatchableError as err:
      respJsonError(err.msg, 401)

  # Let's do authentication first...
  if not req.authHeaderExists():
    raise newException(CatchableError, "The access token is invalid (No auth header present)")
    
  let token = req.getAuthHeader()

  # Check if the token exists in the db
  if not db.tokenExists(token):
    raise newException(CatchableError, "The access token is invalid (token not found in db)")
        
  # Check if the token has a user attached
  if not db.tokenUsesCode(token):
    raise newException(CatchableError, "The access token is invalid (token isn't using an auth code)")
        
  # Double-check the auth code used.
  if not db.authCodeValid(db.getTokenCode(token)):
    raise newException(CatchableError, "The access token is invalid (auth code used by token isn't valid)")
    
  # Check if the client registered to the token
  # has a public oauth scope.
  if not db.hasScope(db.getTokenApp(token), scope):
    raise newException(CatchableError, "The access token is invalid (missing scope) ")