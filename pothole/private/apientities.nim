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
## This module contains all the routes for the instance method in the api


# From somewhere in Quark
import quark/[user, post]

# From somewhere in Pothole
import pothole/[conf, database, routeutils, lib, assets]

# From somewhere in the standard library
import std/[json, times]

proc fields*(user_id: string): JsonNode =
  ## Initialize profile fields
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
    totalPosts = db.getTotalPostsByUserId(user_id)

  configPool.withConnection config:
    avatar = config.getAvatar(user_id)
    header = config.getHeader(user_id)

  return %* {
    "id": user_id,
    "username": user.handle,
    "acct": user.handle,
    "display_name": user.name,
    "locked": user.is_frozen,
    "bot": isBot(user.kind),
    "group": isGroup(user.kind),
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
  let time = now().utc

  configPool.withConnection config:
    return %* {
      "updated_at": $(
        time.format("yyyy-mm-dd") & "T" & time.format("hh:mm:ss") & "Z"
      ),
      "content": config.getStringOrDefault(
        "instance", "description",
        config.getStringOrDefault(
          "instance", "summary", ""
        )
      )
    }

proc v1Instance*(): JsonNode = 
  var
    userCount, postCount, domainCount: int
    admin: string

  dbPool.withConnection db:
    userCount = db.getTotalLocalUsers()
    postCount = db.getTotalPosts()
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
        "version": lib.phVersion,
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
        "version": lib.phVersion,
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
  

