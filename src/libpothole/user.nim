# Copyright © Leo Gavilieau 2022-2023
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# user.nim:
## This module contains various functions and procedures for handling User objects.
## The User object type has been moved here after commit 9f3077d
## Database-related procedures are in db.nim

# From Pothole
import lib, crypto

# From Nim's standard library
import std/strutils except isEmptyOrWhitespace

# A set of characters that you cannot use at all.
# this filters anything that doesn't make a valid email.
const unsafeHandleChars*: set[char] = {
  '!',' ','"', '#','$','%','&','\'',
  '(',')','*','+',',',';','<', '=','>',
  '?','[','\\',']','^','`','{','}','|',
  '~'
}

# A set of characters that you cannot use
# when registering a local user.
const localInvalidHandle*: set[char] = {'@',':','.'}

# User data type.
type 
  User* = object
    id*: string # An unique that represents the actual user
    handle*: string # A string containing the user's actual username 
    name*: string # A string containing the user's display name
    local*: bool # A boolean indicating if this user is from this instance 
    email*: string # A string containing the user's email
    bio*: string # A string containing the user's biography
    password*: string # A string to store a hashed + salted password 
    salt*: string # The actual salt with which to hash the password.
    kdf*: int # Key derivation function version number
    admin*: bool # A boolean indicating if the user is an admin.
    is_frozen*: bool #  A boolean indicating if the user is frozen/banned. 


proc sanitizeHandle*(handle: string): string =
  ## Checks a string against user.unsafeHandleChars
  ## This is mostly used for checking for valid emails and handles.
  if handle.isEmptyOrWhitespace():
    return "" 

  var oldhandle = toLowerAscii(handle)
  result = ""
  for ch in oldhandle:
    if ch notin unsafeHandleChars:
      result.add(ch)

  return result

proc newUser*(handle, name, password: string = "", local,admin: bool = false): User =
  ## This procedure just creates a user and that's it
  ## We will fill out some basic details, like if you supply a password, name
  
  # First off let's do the things that are least likely to create an error in any way possible.
  result = User()
  result.id = randomString()
  result.salt = randomString(32)

  result.kdf = lib.kdf # Always assume user is using latest KDF because why not?
  result.local = local
  result.admin = admin # This is false by default, same with the local thing above.
  result.is_frozen = false # Always assume user isn't frozen. Maybe employ a check in your own software.

  # Sanitize handle before using it
  var newhandle = sanitizeHandle(handle)
  if not isEmptyOrWhitespace(newhandle):
    result.handle = newhandle
  else:
    error "No proper handle was supplied!", "user.newUser()"

  # Use handle as name if name isn't supplied
  if not isEmptyOrWhitespace(name):
    result.name = name
  else:
    result.name = newhandle
  
  if not local and not isEmptyOrWhitespace(password):
    result.password = pbkdf2_hmac_sha512_hash(password, result.salt)
  else:
    result.password = ""

  # The only things remaining are email and bio which the program can guess based on its own context clues (Such as if the user is local)
  return result

proc escape*(user: User, skipChecks: bool = false): User =
  ## A procedure for escaping a User object
  ## skipChecks allows you to skip the essential handle and password checks.
  ## This is only used for potholectl.
  result = user

  # We only need handle and password, the rest can be guessed or blank.
  if not skipChecks:
    if isEmptyOrWhitespace(user.handle):
      error("Missing required fields for adding users\nUser: " & $user,"user.escape")

  result.handle = sanitizeHandle(user.handle)
  result.email = sanitizeHandle(user.email)

  # Use handle as display name if display name doesnt exist or is blank
  if isEmptyOrWhitespace(user.name):
    result.name = user.handle

  # Now we loop over every field and escape it.
  # TODO: Look into using templates or macros to automatically
  #       generate the loop that escapes Users
  #       It could make this code a lot faster.
  for key,val in user.fieldPairs:
    when typeof(val) is bool or typeof(val) is int:
      result.get(key) = val
    when typeof(val) is string:
      result.get(key) = escape(val)

  return result

proc unescape*(user: User): User =
  ## A procedure for unescaping a User object
  result = User()

  # TODO: Look into using templates or macros to automatically
  #       generate the loop that unescapes Users
  for key,val in user.fieldPairs:
    when typeof(val) is bool or typeof(val) is int:
      result.get(key) = val
    when typeof(val) is string:
      result.get(key) = unescape(val,"","")
  
  return result

func `$`*(obj: User): string =
  ## Turns a User object into a human-readable string
  result.add("[")
  for key,val in obj.fieldPairs:
    result.add("\"" & key & "\": \"" & $val & "\",")
  result = result[0 .. len(result) - 2]
  result.add("]")