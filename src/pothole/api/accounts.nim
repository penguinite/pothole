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
# api/accounts.nim:
## This module contains all the routes for the accounts method in the mastodon api.

# From Pothole
import ../db/[oauth, apps, users, auth_codes], ../[strextra, shared, database, conf, routes]

# From somewhere in the standard library
import std/json

# From nimble/other sources
import mummy, iniplus, db_connector/db_postgres

proc accountsVerifyCredentials*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  if not req.authHeaderExists():
    respJsonError("The access token is invalid")
  
  let token = req.getAuthHeader()
  var user = ""

  dbPool.withConnection db:
    # Check if token actually exists
    if not db.tokenExists(token):
      respJsonError("The access token is invalid")
    
    # Check if token is assigned to a user
    if not db.tokenUsesCode(token):
      respJsonError("This method requires an authenticated user", 422)

    user = db.getTokenUser(token)

    # Check if that user's account is frozen (suspended).
    if db.userFrozen(user):
      respJsonError("Your login is currently disabled", 403)
    
    # Check if the user's email has been verified.
    # But only if user.require_verification is true
    configPool.withConnection config:
      if config.getBoolOrDefault("user", "require_verification", false) and not db.userVerified(user):
        respJsonError("Your login is missing a confirmed e-mail address", 403)
    
    # Check if the user's account is pending verification
    if not db.userApproved(user):
      respJsonError("Your login is currently pending approval", 403)

    # Check if the app is actually allowed to access this.
    # We are just checking to see if 
    let app = db.getTokenApp(token)
    if not db.hasScope(app, "read:account") and not db.hasScope(app, "profile"):
      respJsonError("This method requires an authenticated user", 422)

  req.respond(200, headers, $(credentialAccount(user)))

proc accountsGet*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  if not req.pathParams.contains("id"):
    respJsonError("Missing ID parameter")
  
  if req.pathParams["id"].isEmptyOrWhitespace():
    respJsonError("Invalid account id.")
  
  configPool.withConnection config:
    # If the instance has whitelist mode
    # Then check the oauth token.
    if config.getBoolOrDefault("web", "whitelist_mode", false):
      if not req.authHeaderExists():
        respJsonError("This API requires an authenticated user", 401)
      
      let token = req.getAuthHeader()
      dbPool.withConnection db:
        # Check if the token exists in the db
        if not db.tokenExists(token):
          respJsonError("This API requires an authenticated user", 401)
        
        # Check if the token has a user attached
        if not db.tokenUsesCode(token):
          respJsonError("This API requires an authenticated user", 401)
        
        # Double-check the auth code used.
        if not db.authCodeValid(db.getTokenCode(token)):
          respJsonError("This API requires an authenticated user", 401)
        
        # Check if the client registered to the token
        # has a public oauth scope.
        if not db.hasScope(db.getTokenApp(token), "read:accounts"):
          respJsonError("This API requires an authenticated user", 401)

  var result: JsonNode  
  dbPool.withConnection db:
    if not db.userIdExists(req.pathParams["id"]):
      respJsonError("Record not found", 404)
    result = account(req.pathParams["id"])

    # TODO: When support for ActivityPub is added...
    # Hopefully... then implement support for remote users.
    # See the Mastodon API docs.

    if db.userFrozen(req.pathParams["id"]):
      result["suspended"] = newJBool(true)
    
  req.respond(200, headers, $(result))

proc accountsGetMultiple*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  if not req.queryParams.contains("id[]"):
    respJsonError("Missing account ID query parameter.")

  var ids: seq[string] = @[]
  for query in req.queryParams:
    if query[0] == "id[]" and not query[1].isEmptyOrWhitespace():
      ids.add(query[1])
      
  configPool.withConnection config:
    # If the instance has whitelist mode
    # Then check the oauth token.
    if config.getBoolOrDefault("web", "whitelist_mode", false):
      if not req.authHeaderExists():
        respJsonError("This API requires an authenticated user", 401)
      
      let token = req.getAuthHeader()
      dbPool.withConnection db:
        # Check if the token exists in the db
        if not db.tokenExists(token):
          respJsonError("This API requires an authenticated user", 401)
        
        # Check if the token has a user attached
        if not db.tokenUsesCode(token):
          respJsonError("This API requires an authenticated user", 401)
        
        # Double-check the auth code used.
        if not db.authCodeValid(db.getTokenCode(token)):
          respJsonError("This API requires an authenticated user", 401)
        
        # Check if the client registered to the token
        # has a public oauth scope.
        if not db.hasScope(db.getTokenApp(token), "read:accounts"):
          respJsonError("This API requires an authenticated user", 401)

  var result: JsonNode = newJArray()
  for id in ids:
    dbPool.withConnection db:
      if not db.userIdExists(id):
        continue
      var tmp = account(id)

      # TODO: When support for ActivityPub is added...
      # Hopefully... then implement support for remote users.
      # See the Mastodon API docs.

      if db.userFrozen(id):
        tmp["suspended"] = newJBool(true)
      result.elems.add(tmp)
  req.respond(200, headers, $(result))
