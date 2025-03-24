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

template rowParseBool*(str: string) = return str == "t"

func basicEscape(s: string): string =
  for ch in s:
    case ch:
    of '\\',',','"': result.add "\\" & ch
    else: result.add ch

func `!$`*(s: openArray[string]): string =
  ## Converts an openArray[string] into a simple string
  ## suitable for inserting into a database.
  for i in s:
    result.add('\"' & basicEscape(i) & "\",")
  result = '{' & result[0..^2] & '}' 

func toStrSeq*(s: string): seq[string] =
  ## Converts a postgres string array into a real sequence.
  var
    tmp = ""
    backslash = false
    inString = false
  for ch in s[1..^2]:
    # We are dealing with: "a,",b
    if backslash:
      tmp.add(ch)
      backslash = false
      continue

    if inString:

      case ch:
      of '"': inString = false
      of '\\': backslash = true
      else: tmp.add(ch)
    else:
      case ch:
      of '"': inString = true
      of '\\': backslash = true
      of ',':
        result.add tmp
        tmp = ""
      else: tmp.add ch

  if tmp != "":
    result.add(tmp)
  
func smartSplit*(s: string, specialChar: char = '&'): seq[string] =
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
      else:
        if quoted: quoted = false
        else: quoted = true      
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
  
  # If tmp is not empty then split once more!
  # This is to make sure that we're not missing any data.
  # And that's it!
  if tmp != "":
    result.add(tmp)

func htmlEscape*(pre_s: string): string =
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

func `!$`*(date: DateTime): string = 
  ## Converts a date into a database-compatible string
  return format(date, "yyyy-MM-dd HH:mm:ss")

proc toDate*(row: string): DateTime =
  ## Creates a date out of a database row
  return parse(row, "yyyy-MM-dd HH:mm:ss", utc())

func `!$`(pl: PostPrivacyLevel): string =
  return $(pl)

func toLevel*(s: string): PostPrivacyLevel =
  case s:
  of "0": return Public
  of "1": return Unlisted
  of "2": return FollowersOnly
  of "3": return Limited
  of "4": return Private
  else: raise newException(CatchableError, "Unknown string passed to strextra.toLevel(): " & s)