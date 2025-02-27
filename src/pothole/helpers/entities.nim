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
# api/instance.nim:
## This module contains all the code for the API entities.


# From somewhere in Quark
import quark/[users, posts, fields, follows, reactions, boosts, bookmarks, strextra, tag]

# From somewhere in Pothole
import pothole/[conf, database, lib, assets]
import pothole/helpers/routes

# From somewhere in the standard library
import std/[json, times]

# TODO: One easy way to improve performance would be to switch
# to another JSON library such as treeform's jsony or disruptek's jason.
# treeform's jsony is the fastest but it insists on using objects to serialization.
# and that doesn't work well here.

proc formatDate(date: DateTime): string =
  ## Formats dates into a string exactly the way that the API expects.
  # API Example format str:     [YYYY]-[MM]-[DD]T[hh]:[mm]:[ss].[s][TZD]
  # API Example formatted date:  1994 - 11 - 05 T 13 : 15 : 30 . 0  Z
  # Broken example format date:  2025 - 01 - 20 T 04 : 14 : 31 Z
  return date.format("YYYY-MM-dd") & "T" & date.format("hh:mm:ss") & ".000Z"

proc fields*(user_id: string): JsonNode =
  ## Initialize profile fields
  result = newJArray()
  dbPool.withConnection db:
    for key, value, verified, verified_date in db.getFields(user_id).items:
      var jason = %* {
        "name": key,
        "value": value,
      }

      if verified:
        jason["verified_at"] = newJString(verified_date.format("yyyy-mm-dd") & "T" & verified_date.format("hh:mm:ss"))
      else:
        jason["verified_at"] = newJNull()
      result.add(jason)

proc tagHistory(tag: string): seq[JsonNode] =
  var
    postNum, accNum: seq[int]

  dbPool.withConnection db:
    accNum = db.getTagUsageUserNum(tag, days = 7)
    postNum = db.getTagUsagePostNum(tag, days = 7)

  var i = -1
  for date in getTagUsageDays(7):
    inc i
    result.add(
      %* {
        "day": date,
        "uses": postNum[i],
        "accounts": accNum[i]
      }
    )

proc tag*(tag: string, user = ""): JsonNode =
  var
    url = ""
    following = false

  dbPool.withConnection db:
    url = db.getTagUrl(tag)
    if user != "":
      following = db.userFollowsTag(tag, user)

  return %* {
    "name": tag,
    "url": url,
    "history": tagHistory(tag),
    "following": following
  }

proc account*(user_id: string): JsonNode =
  ## Create an account entity
  
  # If user_id is "" then just return JNull()
  # Specs tell us to either keep "contact_account" null or to fill it with a staff member's details.
  # This is used to skip over a conditional in v1Instance and v2Instance
  if user_id == "":
    return newJNull()

  var
    user: User
    avatar, header: string
    followers, following, totalPosts: int

  dbPool.withConnection db:
    user = db.getUserById(user_id)
    followers = db.getFollowersCount(user_id)
    following = db.getFollowingCount(user_id)
    totalPosts = db.getNumPostsByUser(user_id)

  configPool.withConnection config:
    avatar = config.getAvatar(user_id)
    header = config.getHeader(user_id)

  return %* {
    "id": user_id,
    "username": user.handle,
    "acct": user.handle,
    "display_name": user.name,
    "locked": user.is_frozen,
    "bot": user.kind == Application,
    "group": user.kind == Group,
    "discoverable": user.discoverable,
    "created_at": "", # TODO: Implement
    "note": user.bio,
    "url": "",
    "avatar": avatar, # TODO for these 4 media related options: Separate static and animated media.
    "avatar_static": avatar,
    "header": header, 
    "header_static": header,
    "followers_count": followers,
    "following_count": following,
    "statuses_count": totalPosts,
    "last_status_at": "", # Tell me, who the hell is using this?!? WHAT FOR?!?
    "emojis": [], # TODO: I am not sure what this is supposed to be
    "fields": fields(user_id)
  }

proc role*(user_id: string): JsonNode =
  ## Returns a role entity belonging to a user.
  # TODO: Implement more dynamic roles rather than just is_admin and is_moderator
  result = newJObject()
  var is_admin, is_mod: bool
  dbPool.withConnection db:
    is_admin = db.isAdmin(user_id)
    is_mod = db.isModerator(user_id)

  if is_admin:
    return %* {
      "id": "0",
      "name": "Admin",
      "color": "",
      "permissions": "1048575",
      "highlighted": true
    }
    
  if is_mod:
    return %* {
      "id": "1",
      "name": "Moderator",
      "color": "",
      "permissions": "1048575",
      "highlighted": true
    }
  
  
  
proc credentialAccount*(user_id: string): JsonNode =
  ## Create a credential account
  result = account(user_id)
  
  if result.kind == JNull:
    return result

  var
    bio = ""
    followReqCount: int
  
  dbPool.withConnection db:
    bio = db.getUserBio(user_id)
    followReqCount = db.getFollowReqCount(user_id)

  result["source"] = %* {
    "note": bio,
    "fields": fields(user_id),
    "privacy": "public", # TODO: Implement source[privacy] properly
    "sensitive": false, # TODO: Implement source[sensitive] properly
    "language": "en", # TODO: Implement source[language] properly
    "follow_requests_count": followReqCount
   }

  result["role"] = role(user_id)

  return result

proc rules*(): JsonNode =
  result = newJArray()
  configPool.withConnection config:
    var i = 0
    for rule in config.getStringArrayOrDefault("instance", "rules", @[]):
      inc i
      result.add(
        %* {
          "id": $i,
          "text": rule
        }
      )
  return result

proc extendedDescription*(): JsonNode =
  configPool.withConnection config:
    return %* {
      "updated_at": formatDate(now().utc),
      "content": config.getStringOrDefault(
        "instance", "description",
        config.getStringOrDefault(
          "instance", "summary", ""
        )
      )
    }

proc mastoAPIVersion*(): string =
  ## Returns Pothole's version in a way that indicates Mastodon API level support.
  return lib.phMastoCompat & " (compatible; Pothole " & lib.phVersion & ")"

proc v1Instance*(): JsonNode = 
  var
    userCount, postCount, domainCount: int
    admin: string

  dbPool.withConnection db:
    userCount = db.getTotalLocalUsers()
    postCount = db.getNumTotalPosts()
    domainCount = db.getTotalDomains()
    admin = db.getFirstAdmin()

  
  configPool.withConnection config:
    return %*
      {
        "uri": config.getString("instance","uri"),
        "title": config.getString("instance","name"),
        "short_description": config.getString("instance", "summary"),
        "description": config.getStringOrDefault(
          "instance", "description",
          config.getString("instance","summary")
        ),
        "email": config.getStringOrDefault("instance","email",""),
        "version": mastoAPIVersion(),
        "urls": {
          "streaming_api": "wss://" & config.getString("instance","uri") & config.getStringOrDefault("instance", "endpoint", "/")
        },
        "stats": {
          "use_count": userCount,
          "status_count": postCount,
          "domain_count": domainCount
        },
        "thumbnail": config.getStringOrDefault("instance", "logo", ""),
        "languages": config.getStringArrayOrDefault("instance", "languages", @["en"]),
        "registrations": config.getBoolOrDefault("user", "registrations_open", true),
        "approval_required": config.getBoolOrDefault("user", "require_approval", false),
        "configuration": {
          "statuses": {
            "max_characters": config.getIntOrDefault("user", "max_chars", 2000),
            "max_media_attachments": config.getIntOrDefault("user", "max_attachments", 8),
            "characters_reserved_per_url": 23
          },
          "media_attachments": {
            "supported_mime_types":["image/jpeg","image/png","image/gif","image/webp","video/webm","video/mp4","video/quicktime","video/ogg","audio/wave","audio/wav","audio/x-wav","audio/x-pn-wave","audio/vnd.wave","audio/ogg","audio/vorbis","audio/mpeg","audio/mp3","audio/webm","audio/flac","audio/aac","audio/m4a","audio/x-m4a","audio/mp4","audio/3gpp","video/x-ms-asf"],
            "image_size_limit": config.getIntOrDefault("storage","upload_size_limit", 10) * 1000000,
            "image_matrix_limit": 16777216, # I copied this as-is from the documentation cause I will NOT be writing code to deal with media file width and height.
            "video_size_limit": config.getIntOrDefault("storage","upload_size_limit", 10) * 1000000,
            "video_frame_rate_limit": 60, # I also won't be writing code to check for video framerates
            "video_matrix_limit": 2304000 # I copied this as-is from the documentation cause I will NOT be writing code to deal with media file width and height.
          },
          "polls": {
            "max_options": config.getIntOrDefault("instance", "max_poll_options", 20),
            "max_characters_per_option": 100,
            "min_expiration": 300,
            "max_expiration": 2629746
          },
        },
        "contact_account": account(admin),
        "rules": rules()
      }

proc v2Instance*(): JsonNode = 
  var
    totalUsers: int
    admin: string

  dbPool.withConnection db:
    totalUsers = db.getTotalLocalUsers()
    admin = db.getFirstAdmin()

  configPool.withConnection config:
    return %*
      {
        "domain": config.getString("instance","uri"),
        "title": config.getString("instance","name"),
        "version": mastoAPIVersion(),
        "source_url": lib.phSourceUrl,
        "description": config.getStringOrDefault(
          "instance", "description",
          config.getStringOrDefault("instance","summary", "")
        ),
        "usage": {
          "users": {
            "active_month": totalUsers # I am not sure what Mastodon considers "active" to be, but "registered" is good enough for me.
          }
        },
        "thumbail": {
          # The example has blurhash and multiple versions of an image for high-dpi screens.
          # Those are marked optional, so I won't bother implementing them.
          "url": config.getStringOrDefault("instance", "logo", "")
        },
        "languages": config.getStringArrayOrDefault("instance", "languages", @["en"]),
        "configuration": {
          "urls": {
            "streaming_api": "wss://" & config.getString("instance","uri") & config.getStringOrDefault("instance", "endpoint", "/")
          },
          "vapid": {
            "public_key": "" # TODO: Implement vapid keys
          },
          "accounts": {
            "max_featured_tags": config.getIntOrDefault("user","max_featured_tags",10),
            "max_pinned_statuses": config.getIntOrDefault("user","max_pins", 20),
          },
          "statuses": {
            "max_characters": config.getIntOrDefault("user", "max_chars", 2000),
            "max_media_attachments": config.getIntOrDefault("user", "max_attachments", 8),
            "characters_reserved_per_url": 23
          },
          "media_attachments": {
            "supported_mime_types": ["image/jpeg", "image/png", "image/gif", "image/heic", "image/heif", "image/webp", "video/webm", "video/mp4", "video/quicktime", "video/ogg", "audio/wave", "audio/wav", "audio/x-wav", "audio/x-pn-wave", "audio/vnd.wave", "audio/ogg", "audio/vorbis", "audio/mpeg", "audio/mp3", "audio/webm", "audio/flac", "audio/aac", "audio/m4a", "audio/x-m4a", "audio/mp4", "audio/3gpp", "video/x-ms-asf"],
            "image_size_limit": config.getIntOrDefault("storage","upload_size_limit", 10) * 1000000,
            "image_matrix_limit": 16777216,
            "video_size_limit": config.getIntOrDefault("storage","upload_size_limit", 10) * 1000000,
            "video_frame_rate_limit": 60,
            "video_matrix_limit": 2304000,
          },
          "polls": {
            "max_options": config.getIntOrDefault("instance", "max_poll_options", 20),
            "max_characters_per_option": 100,
            "min_expiration": 300,
            "max_expiration": 2629746
          },
          "translation": {
            "enabled": false, # TODO: Switch to on once translation is implemented.
          }
        },
        "registrations": {
          "enabled": config.getBoolOrDefault("user", "registrations_open", true),
          "approval_required": config.getBoolOrDefault("user", "require_approval", true),
          "message": newJNull() # TODO: Maybe let instance admins customize thru a config option
        },
        "contact": {
          "email": config.getStringOrDefault("instance","email",""),
          "account": account(admin)
        },
        "rules": rules()
      }

proc levelToStr*(l: PostPrivacyLevel): string =
  # Our "Private" is the MastoAPI's "direct"
  # Our "FollowersOnly" is the MastoAPI's "private"
  case l:
  of Public: return "public"
  of Unlisted: return "unlisted"
  of FollowersOnly: return "private"
  of Limited: return "limited"
  of Private: return "direct"

proc strToLevel*(s: string): PostPrivacyLevel =
  # Our "Private" is the MastoAPI's "direct"
  # Our "FollowersOnly" is the MastoAPI's "private"
  case s:
  of "public": return Public
  of "unlisted": return Unlisted
  of "private": return FollowersOnly 
  of "limited": return Limited
  of "direct": return Private
  else:
    raise newException(ValueError, "Unacceptable value for converting to Post Privacy Level: " & s)

proc status*(id: string, user_id = ""): JsonNode =
  if id == "": return newJNull()
  else: result = newJObject()

  var
    post: Post
    contents: seq[PostContent] = @[]
    replynum, boostsnum, reactionnums = 0
    replyto_sender = ""

  dbPool.withConnection db:
    post = db.constructPost(db.getPost(id))
    replynum = db.getNumOfReplies(post.id)
    boostsnum = db.getNumOfBoosts(post.id)
    reactionnums = db.getNumOfReactions(post.id)
    if not post.replyto.isEmptyOrWhitespace():
      replyto_sender = db.getPostSender(post.replyto)
    contents = db.getPostContents(post.id)
  
  var realurl = ""
  configPool.withConnection config:
    realurl = realURL(config)
  
  # We could re-write this to avoid declaring an extra variable
  # But then we would have to suffer the overheads of newJString() and getStr()
  # And it's probably best to just keep it this way.
  var tmp = ""
  for content in contents:
    tmp = tmp & contentToHtml(content) & "\n"

  result = %*{
    "id": post.id,
    "uri": realurl & "notice/" & post.id,
    "url": realurl & "notice/" & post.id,
    "created_at": formatDate(post.written),
    "replies_count": replynum,
    "reblogs_count": boostsnum,
    "content": tmp,
    "favourites_count": reactionnums,
    "account": account(post.sender),
    # TODO: Implement the following:
    "media_attachments": [],
    "sensitive": false,
    "spoiler_text": "",
    "language": "en",
    "emojis": newJArray()
  }

  result["visibility"] = newJString(levelToStr(post.level))

  if replyto_sender != "":
    result["in_reply_to_id"] = newJString(post.replyto)
    result["in_reply_to_account_id"] = newJString(replyto_sender)
  else:
    result["in_reply_to_id"] = newJNull()
    result["in_reply_to_account_id"] = newJNull()

  if user_id != "":
    dbPool.withConnection db:
      result["favourited"] = newJBool(db.hasAnyReaction(post.id, user_id))
      result["reblogged"] = newJBool(db.hasAnyBoost(post.id, user_id))
      result["bookmarked"] = newJBool(db.bookmarkExists(user_id, post.id))
      ## TODO: If we have implemented mutes and blocks, then add the muted attribute.
      ## TODO: If we have implemented pinned posts, then add the pinned attribute.
      ## TODO: If we have implemented filters, then add the filtered attribute.
      ## or actually, keep it optional, its alright.