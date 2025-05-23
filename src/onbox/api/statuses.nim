# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
#
# This file is part of Onbox.
# 
# Onbox is free software: you can redistribute it and/or modify it under the terms of
# the GNU Affero General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
# 
# Onbox is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with Onbox. If not, see <https://www.gnu.org/licenses/>. 
# api/statuses.nim:
## This module contains all the routes for the statuses method in the API.

# From somewhere in Onbox
import onbox/[conf, entities, routes, strextra]

# From somewhere in the standard library
import std/[json, strutils]

# From nimble/other sources
import mummy, waterpark/postgres, iniplus,
       amicus/[posts, oauth, boosts, bookmarks, users, tag, shared]

proc postStatus*(req: Request) =
  # TODO: This implementation is extremely basic
  # It doesn't support the following:
  #     - Scheduled posts (minimum 5 mins in the future)
  #     - Idempotency through the Idempotency-Key header
  #     - Media attachments
  #     - Polls
  #     - Sensitivity & Spoiler-text (aka. Content warnings)
  #     - Language
  #
  # And some parts of it could be more well-optimized but I think
  # this works pretty well!

  var
    token, user = ""
    json: JsonNode
  try:
    token = req.verifyClientExists()
    req.verifyClientScope(token, "write:statuses")
    user = req.verifyClientUser(token)
    json = req.fetchReqBody()
  except: return

  var post = newPost()
  post.local = true
  post.sender = user
  post.written = now().utc
  post.level = Public # Public is the default privacy level.

  if json.hasValidStrKey("in_reply_to_id"):
    post.replyto = json["in_reply_to_id"].getStr()
    
  if json.hasValidStrKey("visibility"):
    post.level = strToLevel(json["visibility"].getStr())
  post.content = @[
    PostContent(
      kind: Text,
      txt_format: 0, # 
      txt_published: now().utc,
      text: json["status"].getStr()
    )
  ]

  # Validate post.
  configPool.withConnection config:
    dbPool.withConnection db:
      # Populate post.recipients from the content the user has sent
      if '@' in post.content[0].text:
        post.recipients = @[]
        for handle, domain in parseRecipients(post.content[0].text).items:
          if db.userHandleExists(handle, domain):
            post.recipients.add(db.getIdFromHandle(handle, domain))

      # if this post is a reply to another
      # then check that the original exists
      if post.replyto != "" and not db.postIdExists(post.replyto):
        respJsonError("Post in in_reply_to_id doesn't exist")
      
      post.tags = parseHashtags(post.content[0].text)
      for tag in post.tags:
        if not db.tagExists(tag):
          db.createTag(tag)

      # If the client has requested an idempotency check then we'll perform one.
      if req.headers.contains("Idempotency-Key"):
        # We could probably implement a basic type of idempotency
        # without any extra database tables or overhead.
        # Simply by checking if a post with the same content
        # was made by the same user in the last hour.
        if db.idempotencyCheck(user, post.content[0].text):
          respJsonError("Post was already made, failed idempotency check.")

      # Insert post
      db.addPost(post)

      req.respond(200, createHeaders("application/json"), $(statusJson(db, config, post)))

proc boostStatus*(req: Request) =
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

  var token, user = ""
  try:
    token = req.verifyClientExists()
    req.verifyClientScope(token, "write:statuses")
    user = req.verifyClientUser(token)
  except: return

  # Check if the client has provided a visibility
  var level = Public
  try:
    case req.headers["Content-Type"]:
    of "application/x-www-form-urlencoded":
      level = strToLevel(formToJson(req.body)["visibility"].getStr())
    of "application/json":
      # I wish the API docs forced developers to use one
      # content-type or the other. Instead of having to
      # accept both methods...
      # I saw this being used in the ihabunek/toot client
      level = strToLevel(parseJson(req.body)["visibility"].getStr())
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
    if not db.postIdExists(id) or not db.isBoostable(id):
      respJsonError("Record not found", 404)
    db.addBoost(user, id, level)
    configPool.withConnection config:
      result = status(db, config, id)

  # Here comes the wasteful part.
  # Fuck you MastoAPI.
  # Piece of shit design.
  result["reblog"] = deepCopy(result)
  
  req.respond(200, createHeaders("application/json"), $(result))


proc unboostStatus*(req: Request) =
  var token, user = ""
  try:
    token = req.verifyClientExists()
    req.verifyClientScope(token, "write:statuses")
    user = req.verifyClientUser(token)
  except: return

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    db.removeBoost(user, id)
    configPool.withConnection config:
      req.respond(200, createHeaders("application/json"), $(status(db, config, id)))
  


proc bookmarkStatus*(req: Request) =
  var token, user = ""
  try:
    token = req.verifyClientExists()
    req.verifyClientScope(token, "write:bookmarks")
    user = req.verifyClientUser(token)
  except: return

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    db.bookmarkPost(user, id)

    configPool.withConnection config:
      req.respond(200, createHeaders("application/json"), $(status(db, config, id)))



proc unbookmarkStatus*(req: Request) =
  var token, user = ""
  try:
    token = req.verifyClientExists()
    req.verifyClientScope(token, "write:bookmarks")
    user = req.verifyClientUser(token)
  except: return

  # Check if the post id is valid.
  var id = req.pathParams["id"]
  if id.isEmptyOrWhitespace():
    respJsonError("Invalid post id!", 400)

  dbPool.withConnection db:
    if not db.postIdExists(id):
      respJsonError("Record not found", 404)
    db.unbookmarkPost(id, user)
    configPool.withConnection config:
      req.respond(200, createHeaders("application/json"), $(status(db, config, id)))


proc viewStatus*(req: Request) =
  # TODO: This implementation is seriously deranged...
  # Fix it!

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
      if config.getBoolOrDefault("web", "lockdown_mode", false) or level notin {Public, Unlisted}:
        var token = ""
        try:
          token = req.verifyClientExists()
          req.verifyClientScope(token, "read:statuses")
          discard req.verifyClientUser(token)
        except: return
    
      req.respond(200, createHeaders("application/json"), $(status(db, config, id)))

proc viewBulkStatuses*(req: Request) =
  # TODO: This implementation is seriously deranged...
  # Fix it!

  # Here's what we want to do:
  # First check if the post exists, failing if it doesn't.
  #
  # Then If the instance is in lockdown mode or if the post we want to view
  # is private then we will require authentication with a read or read:statuses scope
  # (Also verifying if the user is allowed to see it.)
  # 
  # Now we return the post.
  var ids: seq[string] = @[]
  try:
    for i in req.fetchReqBody()["id"].getElems():
      ids.add i.getStr()
  except: return

  configPool.withConnection config:
    dbPool.withConnection db:
      var result = newJArray()
      for id in ids:
        if not db.postIdExists(id):
          respJsonError("Record not found", 404)

        let level = db.getPostPrivacyLevel(id)
        if not db.canSeePost(db.getTokenUser(req.getAuthHeader()), id, level):
          respJsonError("Record not found", 404)

        # Check if the instance is in lockdown mode.
        if config.getBoolOrDefault("web", "lockdown_mode", false) or level notin {Public, Unlisted}:
          var token = ""
          try:
            token = req.verifyClientExists()
            req.verifyClientScope(token, "read:statuses")
            discard req.verifyClientUser(token)
          except: return
        
        result.elems.add(status(db, config, id))
      req.respond(200, createHeaders("application/json"), $(result))