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
## This module basically acts as the assets store
import std/tables
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