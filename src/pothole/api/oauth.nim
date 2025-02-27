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
import quark/[strextra, apps, oauth, sessions, auth_codes]

# From somewhere in Pothole
import pothole/[database, conf, assets]
import pothole/helpers/[resp, req, routes]

# From somewhere in the standard library
import std/[json]
import std/strutils except isEmptyOrWhitespace, parseBool

# From nimble/other sources
import mummy, temple

proc success(msg: string): Table[string, string] =
  ## Returns a table suitable for further processing in templateify()
  return {
    "title": "Success!",
    "message_type": "success",
    "message": msg
  }.toTable

proc error(msg: string): Table[string, string] =
  ## Returns a table suitable for further processing in templateify()
  return {
    "title": "Error!",
    "message_type": "error",
    "message": msg
  }.toTable

proc getSeparator(s: string): char =
  ## When given a string containing a set of separated scopes, it tries to find out what the separator is.
  ## This is needed because the Mastodon API allows the use of + signs and spaces as separators.
  ## Personally, I think this is fucking stupid, and it would have made everything easier to just use one symbol.
  for ch in s:
    case ch:
    of '+': return '+'
    of ' ': return ' '
    else: continue
  return ' ' # If a separator can't be found, then it's safe to assume it's a space-separated scope.

proc renderAuthForm(req: Request, scopes: seq[string], client_id, redirect_uri: string) =
  ## A function to render the auth form.
  ## I don't want to repeat myself 2 times in the POST and GET section so...
  ## here it is.
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"

  var human_scopes = ""
  for scope in scopes:
    human_scopes.add(
      "<li>" & scope & ": " & humanizeScope(scope) & "</li>"
    )
  
  let session = req.fetchSessionCookie()
  var appname, login = ""
  dbPool.withConnection db:
    appname = db.getClientName(client_id)
    login = db.getSessionUserHandle(session)

  req.respond(
    200, headers,
    templateify(
      getAsset("oauth.html"),
      {
        "human_scope": human_scopes,
        "scope": scopes.join(" "),
        "login": login,
        "session": session,
        "client_id": client_id,
        "redirect_uri": redirect_uri
      }.toTable
    )
  )

proc redirectToLogin*(req: Request, client, redirect_uri: string, scopes: seq[string], force_login: bool) =
  var headers: HttpHeaders
  # If the client has requested force login then remove the session cookie.
  if force_login:
    headers["Set-Cookie"] = "session=\"\"; path=/; Max-Age=0"

  configPool.withConnection config:
    let url = realURL(config)
    headers["Location"] = url & "auth/sign_in/?return_to=" & encodeQueryComponent("$#oauth/authorize?response_type=code&client_id=$#&redirect_uri=$#&scope=$#&lang=en" % [url, client, redirect_uri, scopes.join(" ")])

  req.respond(
    303, headers, ""
  )
  return

proc oauthAuthorizeGET*(req: Request) =
  # If response_type exists
  if not req.queryParamExists("response_type"):
    respJsonError("Missing required field: response_type")
  
  # If response_type doesn't match "code"
  if req.queryParams["response_type"] != "code":
    respJsonError("Required field response_type has been set to an invalid value.")

  # If client id exists
  if not req.queryParamExists("client_id"):
    respJsonError("Missing required field: response_type")

  # Check if client_id is associated with a valid app
  dbPool.withConnection db:
    if not db.clientExists(req.queryParams["client_id"]):
      respJsonError("Client_id isn't registered to a valid app.")
  var client_id = req.queryParams["client_id"]
  
  # If redirect_uri exists
  if not req.queryParamExists("redirect_uri"):
    respJsonError("Missing required field: redirect_uri")
  var redirect_uri = htmlEscape(req.queryParams["redirect_uri"])

  # Check if redirect_uri matches the redirect_uri for the app
  dbPool.withConnection db:
    if redirect_uri != db.getClientRedirectUri(client_id):
      respJsonError("The redirect_uri used doesn't match the one provided during app registration")

  var
    scopes = @["read"]
    scopeSeparator = ' '
  if req.queryParamExists("scope"):
    # According to API, we can either split by + or space.
    # so we run this to figure it out. Defaulting to spaces if needed
    scopeSeparator = getSeparator(req.queryParams["scope"])
    scopes = req.queryParams["scope"].split(scopeSeparator)
  
    for scope in scopes:
      # Then verify if every scope is valid.
      if not scope.verifyScope():
        respJsonError("Invalid scope: \"" & scope & "\" (Separator: " & scopeSeparator & ")")

  dbPool.withConnection db:
    # And then we see if the scopes have been specified during app registration
    # This isn't in the for loop above, since this uses db calls, and I don't wanna
    # flood the server with excessive database calls.
    if not db.hasScopes(client_id, scopes):
      respJsonError("An attached scope wasn't specified during app registration.")
  
  var force_login = false
  if req.queryParamExists("force_login"):
    try:
      force_login = req.queryParams["force_login"].parseBool()
    except:
      force_login = true
  
  #var lang = "en" # Unused and unparsed. TODO: Implement checks for this.

  # Check for authorization or "force_login" parameter
  # If auth isnt present or force_login is true then redirect user to the login page
  if not req.hasSessionCookie() or force_login:
    req.redirectToLogin(client_id, redirect_uri, scopes, force_login)
    return

  dbPool.withConnection db:
    if not db.sessionExists(req.fetchSessionCookie()):
      req.redirectToLogin(client_id, redirect_uri, scopes, force_login)
      return

  req.renderAuthForm(scopes, client_id, redirect_uri)

proc oauthAuthorizePOST*(req: Request) =
  let fm = req.unrollForm()

  # If response_type exists
  if not fm.formParamExists("response_type"):
    respJsonError("Missing required field: response_type")
  
  # If response_type doesn't match "code"
  if fm["response_type"] != "code":
    respJsonError("Required field response_type has been set to an invalid value.")

  # If client id exists
  if not fm.formParamExists("client_id"):
    respJsonError("Missing required field: response_type")

  # Check if client_id is associated with a valid app
  dbPool.withConnection db:
    if not db.clientExists(fm["client_id"]):
      respJsonError("Client_id isn't registered to a valid app.")
  var client_id = fm["client_id"]
  
  # If redirect_uri exists
  if not fm.formParamExists("redirect_uri"):
    respJsonError("Missing required field: redirect_uri")
  var redirect_uri = htmlEscape(fm["redirect_uri"])

  # Check if redirect_uri matches the redirect_uri for the app
  dbPool.withConnection db:
    if redirect_uri != db.getClientRedirectUri(client_id):
      respJsonError("The redirect_uri used doesn't match the one provided during app registration")

  var
    scopes = @["read"]
    scopeSeparator = ' '
  if fm.formParamExists("scope"):
    # According to API, we can either split by + or space.
    # so we run this to figure it out. Defaulting to spaces if need
    scopeSeparator = getSeparator(fm["scope"])
    scopes = fm["scope"].split(scopeSeparator)
  
    for scope in scopes:
      # Then verify if every scope is valid.
      if not scope.verifyScope():
        respJsonError("Invalid scope: \"" & scope & "\" (Separator: " & scopeSeparator & ")")

  dbPool.withConnection db:
    # And then we see if the scopes have been specified during app registration
    # This isn't in the for loop above, since this uses db calls, and I don't wanna
    # flood the server with excessive database calls.
    if not db.hasScopes(client_id, scopes):
      respJsonError("An attached scope wasn't specified during app registration.")
  
  var force_login = false
  if fm.formParamExists("force_login"):
    try:
      force_login = fm["force_login"].parseBool()
    except:
      force_login = true
  
  # Check for authorization or "force_login" parameter
  # If auth isnt present or force_login is true then redirect user to the login page
  if not req.hasSessionCookie() or force_login:
    req.redirectToLogin(client_id, redirect_uri, scopes, force_login)
    return
  
  dbPool.withConnection db:
    if not db.sessionExists(req.fetchSessionCookie()):
      req.redirectToLogin(client_id, redirect_uri, scopes, force_login)
      return

  if not fm.formParamExists("action"):
    req.renderAuthForm(scopes, client_id, redirect_uri)
    return
  
  var user = ""
  dbPool.withConnection db:
    user = db.getSessionUser(req.fetchSessionCookie())
    if db.authCodeExists(user, client_id):
      db.deleteAuthCode(
        db.getSpecificAuthCode(user, client_id)
      )

  case fm["action"].toLowerAscii():
  of "authorized":
    var code = ""

    dbPool.withConnection db:
      code = db.createAuthCode(user, client_id, scopes.join(" "))
    
    if redirect_uri == "urn:ietf:wg:oauth:2.0:oob":
      ## Show code to user
      var headers: HttpHeaders
      headers["Content-Type"] = "text/html"
      req.respond(
        200, headers,
        templateify(
          getAsset("generic.html"),
          success("Authorization code: " & code)
        )
      )

    else:
      ## Redirect them elsewhere
      var headers: HttpHeaders
      headers["Location"] = redirect_uri & "?code=" & code

      req.respond(
        303, headers, ""
      )
      return
  else:
    # There's not really anything to do.
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    req.respond(
      200, headers,
      templateify(
        getAsset("generic.html"),
        success("Authorization request has been rejected!")
      )
    )

proc oauthToken*(req: Request) =
  var
    grant_type, code, client_id, client_secret, redirect_uri = ""
    scopes = @["read"]

  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  ## We gotta check for both url-form-encoded or whatever
  ## And for JSON body requests.
  case req.headers["Content-Type"]:
  of "application/x-www-form-urlencoded":
    let fm = req.unrollForm()

    # Check if the required stuff is there
    for thing in @["client_id", "client_secret", "redirect_uri", "grant_type"]:
      if not fm.formParamExists(thing): 
        respJsonError("Missing required parameter: " & thing)

    grant_type = fm["grant_type"]
    client_id = fm["client_id"]
    client_secret = fm["client_secret"]
    redirect_uri = fm["redirect_uri"]

    if fm.formParamExists("code"):
      code = fm["code"]
    
    # According to API, we can either split by + or space.
    # so we run this to figure it out. Defaulting to spaces if need
    if fm.formParamExists("scope"):
      scopes = fm["scope"].split(getSeparator(fm["scope"]) )
  of "application/json":
    var json: JsonNode = newJNull()
    try:
      json = parseJSON(req.body)
    except:
      respJsonError("Invalid JSON.")

    # Double check if the parsed JSON is *actually* valid.
    if json.kind == JNull:
      respJsonError("Invalid JSON.")
    
    # Check if the required stuff is there
    for thing in @["client_id", "client_secret", "redirect_uri", "grant_type"]:
      if not json.hasValidStrKey(thing): 
        respJsonError("Missing required parameter: " & thing)

    grant_type = json["grant_type"].getStr()
    client_id = json["client_id"].getStr()
    client_secret = json["client_secret"].getStr()
    redirect_uri = json["redirect_uri"].getStr()

    # Get the website if it exists
    if json.hasValidStrKey("code"):
      code = json["code"].getStr()

    # Get the scopes if they exist
    if json.hasValidStrKey("scope"):
      scopes = json["scope"].getStr().split(getSeparator(json["scope"].getStr()))
  else:
    respJsonError("Unknown content-type.")
  
  for scope in scopes:
    # Verify if scopes are valid.
    if not scope.verifyScope():
      respJsonError("Invalid scope: " & scope)

  if grant_type notin @["authorization_code", "client_credentials"]:
    respJsonError("Unknown grant_type")
  
  var token = ""
  dbPool.withConnection db:
    if not db.clientExists(client_id):
      respJsonError("Client doesn't exist")
    
    if db.getClientSecret(client_id) != client_secret:
      respJsonError("Client secret doesn't match client id")
    
    if db.getClientRedirectUri(client_id) != redirect_uri:
      respJsonError("Redirect_uri not specified during app creation")
    
    if not db.hasScopes(client_id, scopes):
        respJsonError("An attached scope wasn't specified during app registration.")
    
    if grant_type == "authorization_code":
      if not db.authCodeValid(code):
        respJsonError("Invalid code")
      
      scopes = db.getScopesFromCode(code)
      
      if not db.codeHasScopes(code, scopes):
        respJsonError("An attached scope wasn't specified during oauth authorization.")
    
      if db.getTokenFromCode(code) != "":
        respJsonError("Token aleady registered for this auth code.")

    token = db.createToken(client_id, code)
  
  req.respond(
    200, headers,
    $(%*{
      "access_token": token,
      "token_type": "Bearer",
      "scope": scopes.join(" "),
      "created_at": 0
    })
  )
  
proc oauthRevoke*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  ## We gotta check for both url-form-encoded or whatever
  ## And for JSON body requests.
  var client_id, client_secret, token = ""
  case req.headers["Content-Type"]:
  of "application/x-www-form-urlencoded":
    let fm = req.unrollForm()

    # Check if the required stuff is there
    for thing in @["client_id", "client_secret", "token"]:
      if not fm.formParamExists(thing): 
        respJsonError("Missing required parameter: " & thing)

    client_id = fm["client_id"]
    client_secret = fm["client_secret"]
    token = fm["token"]
  of "application/json":
    var json: JsonNode = newJNull()
    try:
      json = parseJSON(req.body)
    except:
      respJsonError("Invalid JSON.")

    # Double check if the parsed JSON is *actually* valid.
    if json.kind == JNull:
      respJsonError("Invalid JSON.")
    
    # Check if the required stuff is there
    for thing in @["client_id", "client_secret", "token"]:
      if not json.hasValidStrKey(thing): 
        respJsonError("Missing required parameter: " & thing)

    client_id = json["client_id"].getStr()
    client_secret = json["client_secret"].getStr()
    token = json["token"].getStr()
  else:
    respJsonError("Unknown content-type.")

  # Now we check if the data submitted is actually valid.
  dbPool.withConnection db:
    if not db.clientExists(client_id):
      respJsonError("Client doesn't exist", 403)
      
    if not db.tokenExists(token):
      respJsonError("Token doesn't exist.", 403)

    if not db.tokenMatchesClient(token, client_id):
      respJsonError("Client doesn't own this token", 403)

    if db.getClientSecret(client_id) != client_secret:
      respJsonError("Client secret doesn't match client id", 403)

    # Finally, delete the OAuth token.
    db.deleteOAuthToken(token)
  # And respond with nothing
  respJson($(%*{}))

  # By the way, how is this API supposed to be idempotent?
  # You're supposed to simultaneously check if the token exists and to let it be deleted multiple times?
  # I think Mastodon either doesn't actually delete the token (they just mark it as deleted, which is stupid)
  # or they don't check for the existence of the token before deleting it.
  # Anyway, this API is not idempotent because thats stupid and there's NO REASON for it to be idempotent in the first place!
  #
  # In our case, if we delete a non-existent OAuth token, then we will get a database error
  
proc oauthInfo*(req: Request) =
  var url = ""
  configPool.withConnection config:
    url = realURL(config)

  respJson($(
    %*{
      "issuer": url,
      "service_documentation": "https://docs.joinmastodon.org/",
      "authorization_endpoint": url & "oauth/authorize",
      "token_endpoint": url & "oauth/token",
      "app_registration_endpoint": url & "api/v1/apps",
      "revocation_endpoint": url & "oauth/revoke",
      # I had to write this manually
      # TODO: It would be nice if we had a way to automate this of some sort.
      "scopes_supported": ["read", "write", "push", "follow", "admin:read", "admin:write", "read:accounts", "read:blocks", "read:bookmarks", "read:favorites", "read:favourites", "read:filters", "read:follows", "read:lists", "read:mutes", "read:notifications", "read:search", "read:statuses", "wite:accounts", "wite:blocks", "wite:bookmarks", "wite:favorites", "wite:favourites", "wite:filters", "wite:follows", "wite:lists", "wite:mutes", "wite:notifications", "wite:search", "wite:statuses", "admin:write:accounts", "admin:write:reports", "admin:write:domain_allows", "admin:write:domain_blocks", "admin:write:ip_blocks", "admin:write:email_domain_blocks", "admin:write:canonical_domain_blocks", "admin:read:accounts", "admin:read:reports", "admin:read:domain_allows", "admin:read:domain_blocks", "admin:read:ip_blocks", "admin:read:email_domain_blocks", "admin:read:canonical_domain_blocks"],
      # The rest we send back as-is, since we don't do things differently.
      "response_types_supported": ["code"],
      "response_modes_supported": ["query", "fragment", "form_post"],
      "code_challenge_methods_supported": ["S256"],
      "grant_types_supported": ["authorization_code", "client_credentials"],
      "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post"]
    }
  ))


