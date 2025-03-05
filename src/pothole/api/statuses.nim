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
# api/statuses.nim:
## This module contains all the routes for the statuses method in the API.


# From somewhere in Quark
import quark/[posts, apps, oauth, auth_codes, boosts, bookmarks, strextra]

# From somewhere in Pothole
import pothole/[database, conf]

# Helper procs
import pothole/helpers/[req,resp,routes,entities]

# From somewhere in the standard library
import std/[json]

# From nimble/other sources
import mummy


proc boostStatus*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  # NONSTANDARD: As far as I am aware, boosts have an ID in Mastodon internally.
  # Like in the database itself, an ID for a boost is made...
  # And the API expects us to return a status entity whose ID is the boost ID.
  # And there's a "reblog" attribute in the JSON which contains another
  # status entity for the post being boosted...
  # ...
  # I decided to skip that bullshit and return a status entity for the post being boosted.
  # listen, when we get a "boost ID" it's gonna be a post ID alongside an authorization header.
  # So why don't we take the the post id and get the user id from the auth header
  # And use that for doing anything boost-related!!!
  #
  # Still, for API compatability reasons, we need to return 2 status entities...
  # Fuck this mastodon API seriously, it's the stupidest, most inefficient bullshit ever!

  # Let's do authentication first...  
  if not req.authHeaderExists():
    respJsonError("The access token is invalid (No auth header present)", 401)
      
  let token = req.getAuthHeader()
  var user = ""
  dbPool.withConnection db:
    # Check if the token exists in the db
    if not db.tokenExists(token):
      respJsonError("The access token is invalid (token not found in db)", 401)
        
    # Check if the token has a user attached
    if not db.tokenUsesCode(token):
      respJsonError("The access token is invalid (token isn't using an auth code)", 401)
        
    # Double-check the auth code used.
    if not db.authCodeValid(db.getTokenCode(token)):
      respJsonError("The access token is invalid (auth code used by token isn't valid)", 401)
    
    # Check if the client registered to the token
    # has a public oauth scope.
    if not db.hasScope(db.getTokenApp(token), "write:statuses"):
      respJsonError("The access token is invalid (scope write or write:statuses is missing) ", 401)

    user = db.getTokenUser(token)

  # Check if the client has provided a visibility
  var level = Public
  try:
    case req.headers["Content-Type"]:
    of "application/x-www-form-urlencoded":
      let form = req.unrollForm()
      if form.formParamExists("visibility"):
        level = strToLevel(form["visibility"])
    of "application/json":
      # I wish the API docs forced developers to use one
      # content-type or the other. Instead of having to
      # accept both methods...
      # I saw this being used in the ihabunek/toot client
      var json: JsonNode = newJNull()
      json = parseJSON(req.body)
      assert json.kind != JNull

      if json.hasValidStrKey("visibility"):
        level = strToLevel(json["visibility"].getStr())
    else: discard
  except:
    level = Public

  # Check if the provided visibility is valid
  # (It can't be a limited or private boost)
  if level == Limited or level == Private:
    respJsonError("Visibility can't be \"direct\" or \"limited\"", 400)


  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  var result = newJObject()
  dbPool.withConnection db:
    if not db.postIdExists(id) or not db.isBoostable(id, user):
      respJsonError("Record not found", 404)
    db.addBoost(id, user, level)

  # Here comes the wasteful part.
  # Fuck you MastoAPI.
  result = status(id)
  result["reblog"] = status(id)

  req.respond(200, headers, $(result))



proc unboostStatus*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  # Let's do authentication first...  
  if not req.authHeaderExists():
    respJsonError("The access token is invalid (No auth header present)", 401)
      
  let token = req.getAuthHeader()
  var user = ""
  dbPool.withConnection db:
    # Check if the token exists in the db
    if not db.tokenExists(token):
      respJsonError("The access token is invalid (token not found in db)", 401)
        
    # Check if the token has a user attached
    if not db.tokenUsesCode(token):
      respJsonError("The access token is invalid (token isn't using an auth code)", 401)
        
    # Double-check the auth code used.
    if not db.authCodeValid(db.getTokenCode(token)):
      respJsonError("The access token is invalid (auth code used by token isn't valid)", 401)
    
    # Check if the client registered to the token
    # has a public oauth scope.
    if not db.hasScope(db.getTokenApp(token), "write:statuses"):
      respJsonError("The access token is invalid (scope write or write:statuses is missing) ", 401)

    user = db.getTokenUser(token)

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id) or not db.isBoostable(id, user):
      respJsonError("Record not found", 404)
    db.removeBoost(id, user)
  
  req.respond(200, headers, $(status(id)))



proc bookmarkStatus*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  # Let's do authentication first...  
  if not req.authHeaderExists():
    respJsonError("The access token is invalid (No auth header present)", 401)
      
  let token = req.getAuthHeader()
  var user = ""
  dbPool.withConnection db:
    # Check if the token exists in the db
    if not db.tokenExists(token):
      respJsonError("The access token is invalid (token not found in db)", 401)
        
    # Check if the token has a user attached
    if not db.tokenUsesCode(token):
      respJsonError("The access token is invalid (token isn't using an auth code)", 401)
        
    # Double-check the auth code used.
    if not db.authCodeValid(db.getTokenCode(token)):
      respJsonError("The access token is invalid (auth code used by token isn't valid)", 401)
    
    # Check if the client registered to the token
    # has a public oauth scope.
    if not db.hasScope(db.getTokenApp(token), "write:bookmarks"):
      respJsonError("The access token is invalid (scope write or write:bookmarks is missing) ", 401)

    user = db.getTokenUser(token)

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    db.bookmarkPost(user, id)

  req.respond(200, headers, $(status(id)))



proc unbookmarkStatus*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  # Let's do authentication first...  
  if not req.authHeaderExists():
    respJsonError("The access token is invalid (No auth header present)", 401)
      
  let token = req.getAuthHeader()
  var user = ""
  dbPool.withConnection db:
    # Check if the token exists in the db
    if not db.tokenExists(token):
      respJsonError("The access token is invalid (token not found in db)", 401)
        
    # Check if the token has a user attached
    if not db.tokenUsesCode(token):
      respJsonError("The access token is invalid (token isn't using an auth code)", 401)
        
    # Double-check the auth code used.
    if not db.authCodeValid(db.getTokenCode(token)):
      respJsonError("The access token is invalid (auth code used by token isn't valid)", 401)
    
    # Check if the client registered to the token
    # has a public oauth scope.
    if not db.hasScope(db.getTokenApp(token), "write:bookmarks"):
      respJsonError("The access token is invalid (scope write or write:bookmarks is missing) ", 401)

    user = db.getTokenUser(token)

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    db.unbookmarkPost(id, user)
  req.respond(200, headers, $(status(id)))


proc viewStatus*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  
  # Here's what we want to do:
  # First check if the post exists, failing if it doesn't.
  #
  # Then If the instance is in lockdown mode or if the post we want to view
  # is private then we will require authentication with a read or read:statuses scope
  # (Also verifying if the user is allowed to see it.)
  # 
  # Now we return the post.

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)
  
  var level = Public
  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    
    level = db.getPostPrivacyLevel(id)
    if not db.canSeePost(db.getTokenUser(req.getAuthHeader()), id, level):
      respJsonError("Record not found", 404)
  
  configPool.withConnection config:
    # Check if the instance is in lockdown mode.
    if config.getBoolOrDefault(Hi"web", "whitelist_mode", false) or level notin {Public, Unlisted}:
      dbPool.withConnection db:
        try:
          req.verifyAccess(db, "read:statuses")
        except CatchableError as err:
          respJsonError(err.msg, 401)

  req.respond(200, headers, $(status(id)))