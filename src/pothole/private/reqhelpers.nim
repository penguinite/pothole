import std/tables
import quark/[strextra, apps, oauth, auth_codes]
import db_connector/db_postgres
import mummy, mummy/multipart
from std/strutils import split

proc isValidQueryParam*(req: Request, query: string): bool =
  ## Check if a query parameter (such as "?query=parameter") is valid and not empty
  return not req.queryParams[query].isEmptyOrWhitespace()

proc getQueryParam*(req: Request, query: string): string =
  ## Returns a query parameter (such as "?query=parameter")
  return req.queryParams[query]

proc isValidPathParam*(req: Request, path: string): bool =
  ## Checks if a path parameter such as /users/{user} is valid and not empty
  return not req.pathParams[path].isEmptyOrWhitespace()

proc getPathParam*(req: Request, path: string): string =
  ## Returns a path parameter such as /users/{user}
  return req.pathParams[path]

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

proc isValidMultipartParam*(mp: MultipartEntries, param: string): bool =
  ## Returns a parameter submitted via a HTML form
  return mp.hasKey(param) and not mp[param].isEmptyOrWhitespace()

proc getMultipartParam*(mp: MultipartEntries, param: string): string =
  ## Checks if a parameter submitted via an HTMl form is valid and not empty
  return mp[param]

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

proc isValidFormParam*(mp: FormEntries, param: string): bool =
  ## Returns a parameter submitted via a HTML form
  return mp.hasKey(param) and not mp[param].isEmptyOrWhitespace()

proc getFormParam*(mp: FormEntries, param: string): string =
  ## Checks if a parameter submitted via an HTMl form is valid and not empty
  return mp[param]

proc hasSessionCookie*(req: Request): bool =
  if not req.headers.contains("Cookie"):
    return false

  var
    val = ""
    flag = false
  for item in req.headers["Cookie"].smartSplit('='):
    if flag:
      val = item
      flag = false
    if item == "session":
      flag = true
  
  if val.isEmptyOrWhitespace() and val != "null":
    return false
  return true

proc fetchSessionCookie*(req: Request): string = 
  var flag = false
  for val in req.headers["Cookie"].smartSplit('='):
    if flag:
      return val
    if val == "session":  
      flag = true

proc getContentType*(req: Request): string =
  result = "application/x-www-form-urlencoded"
  if req.headers.contains("Content-Type"):
    result = req.headers["Content-Type"]
  
  # Some clients such as tuba send their content-type as
  # multipart/form-data; boundary=...
  # And so, we will return everything before
  # the first semicolon 
  if ';' in result:
    result = result.split(';')[0]


proc deleteSessionCookie*(): string = 
  return "session=\"\"; path=/; Max-Age=0"

proc authHeaderExists*(req: Request): bool =
  return req.headers.contains("Authorization") and not isEmptyOrWhitespace(req.headers["Authorization"])

proc getAuthHeader*(req: Request): string =
  let split = req.headers["Authorization"].split("Bearer")

  if len(split) > 1: return split[high(split)].cleanString()
  else: return split[0].cleanString()

proc verifyAccess*(req: Request, db: DbConn, scope: string) =
  runnableExamples:
    ## How to use verifyAccess to ensure a client
    ## is authenticated with the scope "read:statuses"
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