# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
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
# db/timelines.nim:
## This module handles timelines.

import tag, follows, ../strextra
import std/[sequtils, times]
import db_connector/db_postgres

proc getHomeTimeline*(db: DbConn, user: string, limit: var int = 20): seq[string] =
  ## Returns a list of IDs to posts sent by users that `user` follows or in hashtags that `user` follows.
  # Let's see who this user follows 
  var
    following = db.getFollowing(user, limit)
    followingTags = db.getTagsFollowedByUser(user, limit)
  
  # First we check to see if the limit is realistic
  # (ie. do we have enough posts to fill it)
  # If not then we just reset the limit to something sane.

  # Note: Due to a circular dependency on posts, we have to use this
  # Instead of calling getNumTotalPosts()
  let t_limit = len(db.getAllRows(sql"SELECT 0 FROM posts;"))
  if limit > t_limit:
    limit = t_limit

  # We will start by fetching X number of posts from the db
  # (where X is the limit, oh and the order is chronological, according to *creation* date.)
  # And then checking if its creator was followed or if it has a hashtag we follow.
  #
  # This seemed like the best solution at the time given the circumstances
  # But if it isn't then whoopsie! We will make another one!
  # TODO: Help.
  var
    last_date = now().utc
    flag = false
  while len(result) < limit and flag == false:
    for row in db.getAllRows(sql"SELECT id,sender,written FROM posts WHERE date(written) >= ? ORDER BY written ASC LIMIT ?", !$(last_date), $limit):
      if row[1] in following:
        result.add row[0]
        continue
      
      let tags = db.getPostTags(row[0])
      for tag in followingTags:
        if tag in tags:
          result.add row[0]
          continue
    flag = true
    result = result.deduplicate()
  
  # TODO: This does not include posts that have boosts... Too bad!
  return result

proc getTagTimeline*(db: DbConn, tag: string, limit: var int = 20, local = true, remote = true): seq[string] =
  ## Returns a list of IDs to posts in a hashtag.
  ## TODO: Implement.
  return result