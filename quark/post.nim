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
#
# post.nim:
## This module contains various functions and procedures for handling Post objects.
## The Post object type has been moved here after commit 9f3077d
## Database-related procedures are in db.nim

# From somewhere in Quark
import crypto, strextra

# From Nim's standard library
import std/strutils except isEmptyOrWhitespace, parseBool
import std/[tables, times]

# From somewhere else
import rng

export DateTime, parse, format, utc

# ActivityPub Object/Post
type
  PostRevision* = object
    published*: DateTime # The timestamp of when then Post was last edited
    content*: string # The content that this specific revision had.
  
  PostPrivacyLevel* = enum
    Public, Unlisted, FollowersOnly, Private

  Post* = object
    id*: string # A unique id.
    recipients*: seq[string] # A sequence of recipient's handles.
    sender*: string # Basically, the person sending the message (Or more specifically, their ID.)
    replyto*: string # Resource/Post person was replying to,  
    content*: string # The actual content of the post
    written*: DateTime # A timestamp of when the Post was created
    modified*: bool # A boolean indicating whether the Post was edited or not.
    local*:bool # A boolean indicating whether or not the post came from the local server or external servers
    client*: string # A string containing the client id used for writing this post.
    level*: PostPrivacyLevel # The privacy level of the post
    reactions*: Table[string, seq[string]] # A sequence of reactions this post has.
    boosts*: Table[string, seq[string]] # A sequence of id's that have boosted this post. (Along with what level)
    revisions*: seq[PostRevision] # A sequence of past revisions, this is basically copies of post.content

proc newPost*(
    sender, content: string,
    replyto: string = "",
    recipients: seq[string] = @[],
    local: bool = false,
    written: DateTime = now().utc
  ): Post =

  if isEmptyOrWhitespace(sender):
    raise newException(ValueError, "Post is missing sender field.")

  if isEmptyOrWhitespace(content):
    raise newException(ValueError, "Post is missing content field.")

  # Generate post id
  result.id = randstr(32)
  
  # Just do this stuff...
  result.sender = sender
  result.recipients = recipients
  result.local = local
  result.modified = false
  result.content = content
  result.replyto = replyto
  result.written = written
  result.revisions = @[]
  result.level = Public
  result.client = "0"

  return result

func `$`*(obj: Post): string =
  ## Turns a Post object into a human-readable string
  result.add("[")
  for key,val in obj.fieldPairs:
    result.add("\"" & key & "\": \"" & $val & "\",")
  result = result[0 .. len(result) - 2]
  result.add("]")

proc escapeCommas*(str: string): string = 
  ## A proc that escapes away commas only.
  ## Use toString, toSeq or whatever else you need.
  ## This is a bit low-level
  if isEmptyOrWhitespace(str): return str
  for ch in str:
    # Comma handling
    case ch:
    of ',': result.add("\\,")
    else: result.add(ch)
  return result

proc unescapeCommas*(str: string): seq[string] =
  ## A proc that unescapes commas only.
  var
    tmp = ""
    backslash = false
  for ch in str:
    case ch:
    of '\\':
      if backslash:
        tmp.add(ch)
      else:
        backslash = true
    of ',':
      if backslash:
        tmp.add(",")
        backslash = false
      else:
        result.add(tmp)
        tmp = ""
    else:
      if backslash:
        tmp.add("\\")
        backslash = false
      tmp.add(ch)

  if len(tmp) > 0:
    result.add(tmp)
    tmp = ""
  
  return result

proc toString*(sequence: seq[string]): string =
  for item in sequence:
    result.add(escapeCommas(item) & ",")
  if len(result) != 0:
    result = result[0..^2]
  return result

proc toSeq*(str: string): seq[string] =
  return unescapeCommas(str)

proc toDbString*(date: DateTime): string = 
  try:
    return format(date, "yyyy-MM-dd HH:mm:ss")
  except:
    return now().format("yyyy-MM-dd HH:mm:ss")

proc toDateFromDb*(str: string): DateTime =
  try:
    return parse(str, "yyyy-MM-dd HH:mm:ss", utc())
  except:
    return now()

proc formatDate*(dt: DateTime): string =
  try:
    dt.format("MMM d, YYYY HH:mm")
  except:
    return now().format("MMM d, YYYY HH:mm")

proc toString*(revisions: seq[PostRevision]): string =
  discard # TODO

proc toPostRevisionsSeq*(str: string): seq[PostRevision] =
  discard # TODO

proc toString*(lvl: PostPrivacyLevel): string =
  case lvl:
  of Public: return "0"
  of Unlisted: return "1"
  of FollowersOnly: return "2"
  of Private: return "3"

proc toPostPrivacyLevel*(lvl: string): PostPrivacyLevel =
  case lvl:
  of "0": return Public
  of "1": return Unlisted
  of "2": return FollowersOnly
  of "3": return Private
  else:
    return Public

proc toPostPrivacyLevel*(lvl: int): PostPrivacyLevel =
  case lvl:
  of 0: return Public
  of 1: return Unlisted
  of 2: return FollowersOnly
  of 3: return Private
  else:
    return Public