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
# api/oauth.nim:
## This module contains all the routes for the oauth method in the api


# From somewhere in Quark
import quark/[follows, apps, oauth, auth_codes, strextra]

# From somewhere in Pothole
import pothole/[database, conf]

# Helper procs
import pothole/helpers/[req, resp, routes, entities]

# From somewhere in the standard library
import std/[json]
import std/strutils except isEmptyOrWhitespace, parseBool

# From nimble/other sources
import mummy

proc timelinesHome*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  
  # TODO: Implement pagination *properly*
  # If any of these are present, then just error out.
  for i in @["max_id", "since_id", "min_id"]:
    if req.queryParamExists(i):
      respJson("You're using a pagination feature and I honest to goodness WILL NOT IMPLEMENT IT NOW", 500)
  
  # Now we can begin actually implementing the API
  
  # Parse ?limit=x
  # If ?limit isn't present then default to 20 posts
  var limit = 20

  if req.queryParamExists("limit"):
    limit = parseInt(req.queryParams["limit"])

  if limit > 40:
    # MastoAPI docs sets a limit of 40.
    # So we will throw an error if it is over 40
    respJsonError("Limit cannot be over 40", 401)

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
    if not db.hasScope(db.getTokenApp(token), "read:statuses"):
      respJsonError("The access token is invalid (scope read or read:statuses is missing) ", 401)

    user = db.getTokenUser(token)

  var result = newJArray()

  dbPool.withConnection db:
    for postId in db.getHomeTimeline(user, limit):
      result.elems.add(status(postId))
  req.respond(200, headers, $(result))



proc timelinesHashtag*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  
  # TODO: Implement pagination *properly* and tag searching
  # If any of these are present, then just error out.

  for i in @["max_id", "since_id", "min_id", "any", "all", "none"]:
    if req.queryParamExists(i):
      respJson("You're using an unsupported feature and I honest to goodness WILL NOT IMPLEMENT IT NOW", 500)
  
  # These booleans control which types of post to show
  # Fx. if local is disabled then we won't include local posts
  # if remote is disabled then we won't include remote posts
  # if both are enabled (the default) then we will include all types of post.
  var local, remote = true

  # The mastodon API has 2 query parameters for this API endpoint
  # local, which when set to true, tells the server to include only local posts
  # and remote which does the same as local but with remote posts instead.
  # Both are set to false...
  if req.queryParamExists("local"):
    local = parseBool(req.queryParams["local"])
    remote = not parseBool(req.queryParams["local"])

  if req.queryParamExists("remote"):
    remote = parseBool(req.queryParams["remote"])
    local = not parseBool(req.queryParams["remote"])
  
  var onlyMedia = false
  # TODO: Implement the "only_media" query parameter for this API endpoint.
  # We dont have media handling yet and so we can't test it.

  # If ?limit isn't present then default to 20 posts
  var limit = 20

  if req.queryParamExists("limit"):
    limit = parseInt(req.queryParams["limit"])

  if limit > 40:
    # MastoAPI docs sets a limit of 40.
    # So we will throw an error if it is over 40
    respJsonError("Limit cannot be over 40", 401)

  configPool.withConnection config:
    if config.getBoolOrDefault("web", "whitelist_mode", false):
      dbPool.withConnection db:
        try:
          req.verifyAccess(db, "read:statuses")
        except CatchableError as err:
          respJsonError(err.msg, 401)

  var result = newJArray()

  dbPool.withConnection db:
    for postId in db.getTagTimeline(req.pathParams["tag"], limit, local, remote):
      result.elems.add(status(postId))
  req.respond(200, headers, $(result))
