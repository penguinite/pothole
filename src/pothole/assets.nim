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
# assets.nim:
## This module basically acts as the assets store and it contains a quick templating library
## When compilling, we expect all of the built-in assets to be stored in the assets/ folder.
## On startup, we will load all of these and do some special operation to some modules.
## (Ie. index.html, the pothole main webpage, will need to be compiled with the built-in quick template library.)
import std/os, pothole/[conf]
import std/strutils except isEmptyOrWhitespace, parseBool

proc initUploads*(config: ConfigTable): string =
  ## Initializes the upload folder by checking if the user has already defined where it should be
  ## and creating the folder if it doesn't exist.
  result = config.getStringOrDefault("folders", "uploads", "uploads/")
  
  if not result.endsWith("/"):
    result.add("/")

  if not dirExists(result):
    createDir(result)

  return result

proc getAsset*(fn: string): string =
  # Get static asset
  const table = {
    "oauth.html": staticRead("../assets/oauth.html"),
    "signin.html": staticRead("../assets/signin.html"),
    "generic.html": staticRead("../assets/generic.html"),
    "home.html": staticRead("../assets/home.html"),
    "style.css": staticRead("../assets/style.css")
  }.toTable
  return table[fn]