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
import quark/[tag, apps, oauth, auth_codes]

# From somewhere in Pothole
import pothole/[database]

# Helper procs
import pothole/helpers/[routes, req, resp, entities]

# From somewhere in the standard library
import std/[json]
import std/strutils except isEmptyOrWhitespace, parseBool

# From nimble/other sources
import mummy

proc followedTags*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  
  
  # TODO: Implement pagination *properly*
  # If any of these are present, then just error out.
  for i in @["max_id", "since_id", "min_id"]:
    if req.queryParamExists(i):
      respJson("You're using a pagination feature and I honest to goodness WILL NOT IMPLEMENT IT NOW", 500)
  
  # Same thing for the Link http header
  if req.headers.contains("Link"):
    respJson("You're using a pagination feature and I honest to goodness WILL NOT IMPLEMENT IT NOW", 500)

  # Now we can begin actually implementing the API

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
    if not db.hasScope(db.getTokenApp(token), "read:follows"):
      respJsonError("The access token is invalid (scope read or read:follows is missing) ", 401)

    user = db.getTokenUser(token)

  var result = newJArray()
  
  # Parse ?limit=x
  # If ?limit isn't present then default to 100
  var limit = 100

  if req.queryParams.contains("limit"):
    try:
      limit = parseInt(req.queryParams["limit"])
    except:
      limit = 100
  
  if limit > 200:
    # MastoAPI docs sets a limit of 200.
    # So we will throw an error if it is over 200.
    respJsonError("Limit cannot be over 200", 401)

  dbPool.withConnection db:
    for tag in db.getTagsFollowedByUser(user, limit):
      result.elems.add(tag(tag))
  req.respond(200, headers, $(result))
