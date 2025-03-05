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
#
# quark/new/post.nim:
## This module contains all the logic for handling posts.
## 
## Including basic processing, database storage,
## database retrieval, modification, deletion and so on
## and so forth.

# From Quark
import quark/private/[macros, database]
import quark/[strextra, shared, tag, follows]
export shared

# From the standard library
import std/[tables, times]
from std/strutils import split

# From elsewhere
import db_connector/db_postgres, rng

export Post, PostPrivacyLevel, PostContent, PostContentType

# Game plan when inserting a post:
# Insert the post
# Insert the post content
#
# Game plan when post is edited (text only):
# Create a new "text content" row in the db
# Update any other columns accordingly (Setting latest to false)
# Create a new "post content" row in the db and set it accordingly.
# Update any other attributes accordingly (For example, the client, the modified bool, the recipients, the level)
# 
# Game plan when post is edited (For non-archived types of content, such as polls):
# Remove existing content row
# Create new one

proc newPost*(
  sender: string, content: seq[PostContent], recipients: seq[string] = @[],
  replyto = "", written = now().utc, modified = false, local = true,
  level = Public, id = randstr(32), client = "0",
  reactions = initTable[string,seq[string]](),
  boosts = initTable[string,seq[string]]()
): Post =
  return Post(
    id: id,
    recipients: recipients,
    sender: sender,
    replyto: replyto,
    content: content,
    written: written,
    modified: modified,
    local: local,
    client: client,
    level: level,
    reactions: reactions,
    boosts: boosts
  )

proc text*(content: string, date: DateTime = now().utc, format = "txt"): PostContent =
  result = PostContent(kind: Text)
  result.text = content
  result.published = date
  result.format = format
  return result

proc constructPost*(db: DbConn, row: Row): Post =
  ## Converts a post minimally.
  ## This means no reactions, no boosts
  ## and no post content.
  
  var i: int = -1;

  for key,value in result.fieldPairs:
    # Skip the fields that are processed by *other* bits of code.
    when result.get(key) isnot Table[string, seq[string]] and result.get(key) isnot seq[PostContent]:
      inc(i)

    when result.get(key) is bool:
      result.get(key) = parseBool(row[i])
    when result.get(key) is string:
      result.get(key) = row[i]
    when result.get(key) is seq[string]:
      result.get(key) = split(row[i], ",")

      # the split() proc sometimes creates items in the sequence
      # even when there isn't. So this bit of code manually
      # clears the list if two specific conditions are met.
      if len(result.get(key)) == 1 and result.get(key)[0] == "":
        result.get(key) = @[]
    when result.get(key) is DateTime:
      result.get(key) = toDateFromDb(row[i])
    when result.get(key) is PostPrivacyLevel:
      result.get(key) = toPrivacyLevelFromDb(row[i])
  return result

proc addPost*(db: DbConn, post: Post) =
  ## A function add a post into the database
  ## This function uses parameterized substitution
  ## So escaping objects before sending them here is not a requirement.
  
  let testStatement = sql"SELECT local FROM posts WHERE id = ?;"

  if db.getRow(testStatement, post.id).has():
    raise newException(DbError, "Post with id \"" & post.id & "\" already exists.")

  # TODO: Prettify this.
  db.exec(
    sql"INSERT INTO posts (id,recipients,sender,replyto,written,modified,local,client,level) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
    post.id,
    toDbString(post.recipients),
    post.sender,
    post.replyto,
    toDbString(post.written),
    post.modified,
    post.local,
    post.client,
    toDbString(post.level)
  )

  # Handle post "contents"
  for content in post.content:
    case content.kind:
    of Text:
      # Insert post text
      db.exec(
        sql"INSERT INTO posts_text (pid,content,format,published,latest) VALUES (?,?,?,?,?);",
        post.id, content.text, content.format, toDbString(content.published), true
      )

      # And then insert the post content
      db.exec(
        sql"INSERT INTO posts_content (pid,kind,cid) VALUES (?,?,?);",
        post.id, "0", ""
      )
    of Tag:
      # Hashtag usage is just tracked by inserting a value into the posts_tag table

      # So first, we check if the hashtag exists in the first place.
      # Creating it if it doesn't. Cause there's a foreign_key on posts_tag.tag
      if not db.tagExists(content.tag_used):
        db.createTag(content.tag_used)
      db.exec(
        sql"INSERT INTO posts_tag VALUES (?,?,?,?);",
        post.id, content.tag_used, post.sender, toDbString(content.tag_date)
      )

      # Note: For rowToContent (and all the functions that depend on it) to work
      # We need to insert the tag into posts_tag as well...
      #
      # TODO: This seems stupid and inefficient... Because it is...
      # Find out a way to remove posts_content or posts_tag
      db.exec(
        sql"INSERT INTO posts_content (pid,kind,cid) VALUES (?,?,?);",
        post.id, "4", content.tag_used
      )
    else:
      # If you encounter this error then flag it immediately to the devs.
      raise newException(DbError, "Unknown post content type: " & $(content.kind))

proc postIdExists*(db: DbConn, id: string): bool =
  ## A function to see if a post id exists in the database
  ## The id supplied can be plain and un-escaped. It will be escaped and sanitized here.
  return has(db.getRow(sql"SELECT local FROM posts WHERE id = ?;", id))

proc updatePost*(db: DbConn, id, column, value: string) =
  ## A procedure to update a post using it's ID.
  ## Like with the updateUserByHandle and updateUserById procedures,
  ## the value parameter should be heavily sanitized and escaped to prevent a class of awful security holes.
  ## The id can be passed plain, it will be escaped.
  db.exec(sql("UPDATE posts SET " & column & " = ? WHERE id = ?;"), value, id)

proc getPost*(db: DbConn, id: string): Row =
  ## Retrieve a post using an ID.
  ## 
  ## You will need to pass this on further to constructPost()
  ## or it's semi and full variants. As this just returns a database row.
  let post = db.getRow(sql"SELECT * FROM posts WHERE id = ?;", id)
  if not post.has():
    raise newException(DbError, "Couldn't find post with id \"" & id & "\"")
  return post

proc getPostsByUser*(db: DbConn, id: string, limit: int = 15): seq[string] = 
  ## A procedure that only fetches the IDs of posts made by a specific user.
  ## This is used to quickly get a list over every post made by a user, for, say,
  ## potholectl or a pothole admin frontend.
  var sqlStatement = sql"SELECT id FROM posts WHERE sender = ?;"
  if limit != 0:
    sqlStatement = sql("SELECT id FROM posts WHERE sender = ? LIMIT " & $limit & ";")

  for post in db.getAllRows(sqlStatement, id):
    result.add(post[0])
  return result

proc getNumPostsByUser*(db: DbConn, id: string): int =
  ## Returns the number of posts made by a specific user.
  return len(db.getAllRows(sql"SELECT 0 FROM posts WHERE sender = ?;", id))

proc rowToContent*(db: DbConn, row: Row, pid: string): PostContent =
  ## Converts a row consisting of a kind, and cid into a proper PostContent object.
  ## 
  ## Note: This makes extra calls to the database depending on the type.
  case row[0]
  of "0": # Text kind
    # We must fetch from posts_text.
    let textRow = db.getRow(sql"SELECT content,format,published FROM posts_text WHERE pid = ?;", pid)
    return PostContent(
      kind: Text,
      text: textRow[0],
      format: textRow[1],
      published: toDateFromDb(textRow[2])
    )
  of "4": # Hashtag
    # We do need to fetch the date when the tag was used from posts_tag
    return PostContent(
      kind: Tag,
      tag_used: row[1],
      tag_date: toDateFromDb(db.getRow(sql"SELECT use_date FROM posts_tag WHERE pid = ? and tag = ?;", pid, row[1])[0])
    )
  else:
    # If you encounter this error then flag it immediately to the devs.
    raise newException(DbError, "Unknown post content type: " & row[0])

proc getPostContents*(db: DbConn, id: string): seq[PostContent] = 
  for row in db.getAllRows(sql"SELECT kind,cid FROM posts_content WHERE pid = ?;", id):
    result.add(db.rowToContent(row, id))
  return result

proc getNumTotalPosts*(db: DbConn, local = true): int =
  ## A procedure to get the total number of posts. You can choose where or not they should be local-only with the local parameter.
  result = 0
  case local:
  of true:
    for x in db.getAllRows(sql("SELECT 0 FROM posts WHERE local = 'true';")):
      inc(result)
  of false:
    for x in db.getAllRows(sql("SELECT 0 FROM posts;")):
      inc(result)
  return result

proc deletePost*(db: DbConn, id: string) = 
  db.exec(sql"DELETE FROM posts WHERE id = ?;", id)

proc getNumOfReplies*(db: DbConn, post_id: string): int =
  return len(db.getAllRows(sql"SELECT 0 FROM posts WHERE replyto = ?;", post_id))

proc getPostSender*(db: DbConn, post_id: string): string =
  return db.getRow(sql"SELECT sender FROM posts WHERE id = ?;", post_id)[0]

proc updatePostSender*(db: DbConn, post_id, sender: string) =
  ## Updates the `sender` for any post
  ## 
  ## Used when deleting users, since we can save on processing costs
  ## by marking posts as "deleted" or "unavailable"
  ## (And this, we do by setting the sender to null)
  db.exec(sql"UPDATE posts SET sender = ? WHERE id = ?;", sender, post_id)

proc getLocalPosts*(db: DbConn, limit: int = 15): seq[Row] =
  ## A procedure to get posts from local users only.
  ## Set limit to 0 to disable the limit and get all posts from local users.
  ## 
  ## This returns seq[Row], so you might want to pass it on to a constructPost() like proc.
  
  var sqlStatement: SqlQuery
  if limit != 0:
    sqlStatement = sql("SELECT * FROM posts WHERE local = TRUE LIMIT " & $limit & ";")
  else:
    sqlStatement = sql("SELECT * FROM posts WHERE local = TRUE;")
  
  for post in db.getAllRows(sqlStatement):
    result.add(post)
  return result

import packages/docutils/[rst, rstgen], std/strtabs

proc contentToHtml*(content: PostContent): string =
  ## Converts a PostContent object into safe, sanitized HTML. Ready for displaying!
  case content.kind:
  of Text:
    ## TODO: Add support for HTML, ie. do HTML sanitization the way that Mastodon does it.
    case content.format:
    of "txt", "plain":
      result.add("<p>" & safeHtml(content.text) & "</p>")
    of "md":
      result.add(rstToHtml(
          safeHtml(content.text), {roPreferMarkdown}, newStringTable()
        )
      )
    of "rst":
      result.add(
        rstToHtml(safeHtml(content.text), {}, newStringTable())
      )
    else: raise newException(ValueError, "Unexpected text format: " & $(content.format))
  else: raise newException(ValueError, "Unexpected content type: " & $(content.kind))
  return result

proc getPostPrivacyLevel*(db: DbConn, id: string): PostPrivacyLevel =
  return toPrivacyLevelFromDb(db.getRow(sql"SELECT level FROM posts WHERE id =?;", id)[0])

proc getSender*(db: DbConn, pid: string): string =
  return db.getRow(sql"SELECT sender FROM posts WHERE id = ?;", pid)[0]

proc getRecipients*(db: DbConn, pid: string): seq[string] =
  result = split(db.getRow(sql"GET recipients FROM posts WHERE id = ?;", pid)[0], ",")

  # the split() proc sometimes creates items in the sequence
  # even when there isn't. So this bit of code manually
  # clears the list if two specific conditions are met.
  if len(result) == 1 and result[0] == "":
    result = @[]
  return result

proc canSeePost*(db: DbCOnn, uid, pid: string, level: PostPrivacyLevel): bool =
  case level:
  of Public, Unlisted:
    # Of course the user is allowed to see these...
    return true
  of FollowersOnly:
    # Check if user is following sender
    # If so, then yes, they can see the post.
    return db.getFollowStatus(uid, db.getSender(pid)) == AcceptedFollowRequest
  of Limited, Private:
    # TODO: Limited is different from Private but the MastoAPI docs don't clarify hpw.
    # Please figure out the difference and fix this bug.
    # For now, we will check if the user has been directly mentioned in the post they
    # want to see.
    return uid in db.getRecipients(pid)