# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
# Copyright © penguinite 2024 <penguinite@tuta.io>
#
# This file is part of Pothole. Specifically, the Quark repository.
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
# strextra.nim:
## This module provides complementary string handling functions,
## such as functions for converting various datatypes to and from
## strings (for, say, database-compatability) or it might provide
## some new functionality not in std/strutils but too useless by itself
## to justify a new module.
## 
## This also imports and exports std/strutils

# From Pothole
import pothole/shared

# From the standard library
import std/[times, strutils]
export strutils

func parseBool*(str: string): bool = 
  ## I'll have to add this because strutils.parseBool() does not support "t" and "f"
  ## And I think the reason for this inclusion was that db_postgres or something db-related was returning "t" and "f" for booleans.
  ## And since parseBool() did not support this, it was messing up the entire database logic of pothole.
  ## TODO: Submit a PR to nim upstream to add "t" and "f" in parseBool()
  case str.toLowerAscii():
  of "y", "yes", "true", "1", "on", "t": return true
  of "n", "no", "false", "0", "off", "f", "": return false

proc smartSplit*(s: string, specialChar: char = '&'): seq[string] =
  ## A split function that is both aware of quotes and backslashes.
  ## Aware, as in, it won't split if it sees the specialCharacter surrounded by quotes, or backslashed.
  ## 
  ## Used in (and was originally written for) `pothole/routeutils.nim:unrollForm()`
  var
    quoted, backslash = false
    tmp = ""
  for ch in s:
    case ch:
    of '\\':
      # If a double backslash has been detected then just
      # insert a backslash into tmp and set backslash to false
      if backslash:
        backslash = false
        tmp.add(ch)
      else:
        # otherwise, set backslash to true
        backslash = true
    of '"', '\'': # Note: If someone mixes and matches quotes in a form body then we're fucked but it doesn't matter either way.
      # If a backslash was previously detected then
      # add double quotes to tmp instead of toggling the quoted flag
      if backslash:
        tmp.add(ch)
        backslash = false
        continue

      if quoted:
        quoted = false
      else:
        quoted = true      
    else:
      # if the character we are currently parsing is the special character then
      # check we're not in backslash or quote mode, and if not
      # then finally split.
      if ch == specialChar:
        if backslash or quoted:
          tmp.add(ch)
          continue

        result.add(tmp)
        tmp = ""
        continue
      
      # otherwise, just check for backslash and add it to tmp if it isn't backslashed.
      if backslash:
        continue
      tmp.add(ch)
  
  # If tmp is not empty then split!
  if tmp != "":
    result.add(tmp)

  # Finally, the good part, return result.
  return result

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

proc htmlEscape*(pre_s: string): string =
  ## Very basic HTML escaping function.
  var s = pre_s
  if s.startsWith("javascript:"):
    s = s[11..^1]
  if s.startsWith("script:"):
    s = s[7..^1]
  if s.startsWith("java:"):
    s = s[5..^1]

  for ch in s:
    case ch:
    of '<':
      result.add("&lt;")
    of '>':
      result.add("&gt;")
    else:
      result.add(ch)

## This next section provides the database compatability procedures
## That were briefly mentioned in the documentation for this module
## 
## The only reason they weren't higher up is because I think they're
## boring and repetitive for the most part.

proc toDbString*(pt: PostContentType): string =
  ## Converts a post content type into a database-compatible string
  return $(pt)

proc toDbString*(sequence: seq[string]): string =
  ## Converts a string sequence into a database-compatible string
  for item in sequence:
    result.add(escapeCommas(item) & ",")
  if len(result) != 0:
    result = result[0..^2]
  return result

proc toDbString*(pl: PostPrivacyLevel): string =
  ## Converts a post privacy level into a database-compatible string
  case pl:
  of Public: return "0"
  of Unlisted: return "1"
  of FollowersOnly: return "2"
  of Private: return "3"
  of Limited: return "4"

proc toDbString*(date: DateTime): string = 
  ## Converts a date into a database-compatible string
  try:
    return format(date, "yyyy-MM-dd HH:mm:ss")
  except:
    return now().format("yyyy-MM-dd HH:mm:ss")

proc toDateFromDb*(row: string): DateTime =
  ## Creates a date out of a database row
  try:
    return parse(row, "yyyy-MM-dd HH:mm:ss", utc())
  except:
    return now()

proc toPrivacyLevelFromDb*(row: string): PostPrivacyLevel =
  ## Creats a post privacy level object out of a database row
  case row:
  of "0": return Public
  of "1": return Unlisted
  of "2": return FollowersOnly
  of "3": return Private
  of "4": return Limited
  else:
    return Public

proc toSeqFromDb*(row: string): seq[string] =
  ## Creates a sequence containing strings from a database row
  result = split(row, ",")

  # the split() proc sometimes creates items in the sequence
  # even when there isn't. So this bit of code manually
  # clears the list if two specific conditions are met.
  if len(result) == 1 and result[0] == "":
    result = @[]

proc toContentTypeFromDb*(row: string): PostContentType =
  ## A procedure to convert a string (fetched from the Db)
  ## to a PostContentType
  case row:
  of "0": return Text
  of "1": return Poll
  of "2": return Media
  of "4": return Tag
  
proc toKdfFromDb*(num: string): KDF =
  ## Converts a string to a KDF object.
  ## You can use this instead of IntToKDF for when you are dealing with database rows.
  ## (Which, in db_postgres, consist of seq[string])
  case num:
  of "1": return PBKDF_HMAC_SHA512

proc toDbString*(kdf: KDF): string = 
  ## Converts a KDF object into a string.
  ## You could use to save nanoseconds when dealing with database logic.
  ## Honestly though, it might be too much. Even for me.
  return $(kdf)

proc toHumanString*(kdf: KDF): string =
  ## Converts a KDF into a human-readable string.
  case kdf:
  of PBKDF_HMAC_SHA512: return "PBKDF_HMAC_SHA512 (210000 iterations, 32 outlength)"

func toUserType*(s: string): UserType =
  ## Converts a plain string into a UserType
  case s:
  of "Person": return Person
  of "Application": return Application
  of "Organization": return Organization
  of "Group": return Group
  of "Service": return Service
  else: return Person

func toString*(t: UserType): string =
  result = case t:
    of Person: "Person"
    of Application: "Application"
    of Organization: "Organization"
    of Group: "Group"
    of Service: "Service"

func `$`*(t: UserType): string = return toString(t)

proc safeHtml*(s: string): string =
  ## Converts any greater-than and less-than signs to a sanitized HTML equivalent
  for ch in s:
    case ch:
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    else: result.add ch
  return result