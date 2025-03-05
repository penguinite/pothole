-- UTF-8 is best.
SET client_encoding = 'UTF8';

-- Needed to work around https://github.com/nim-lang/db_connector/issues/19
-- Without this, it might be possible to do SQL injection.
-- TODO: Fix this in the db_connector library so that everyone can enjoy injection-free data operations.
SET standard_conforming_strings = on;

-- id, TEXT PRIMARY KEY NOT NULL UNIQUE: The client Id for the application
-- secret, TEXT NOT NULL UNIQUE: The client secret for the application
-- scopes, TET NOT NULL: Scopes of this application, space-separated.
-- redirect_uri, TEXT DEFAULT 'urn:ietf:wg:oauth:2.0:oob': The redirect uri for the app
-- name, TEXT: Name of application
-- link, TEXT: The homepage or source code link to the application
-- last_accessed, TIMESTAMP: Last used timestamp, when this is older than 2 weeks, the row is deleted.
CREATE TABLE IF NOT EXISTS apps (id TEXT PRIMARY KEY NOT NULL UNIQUE, secret TEXT NOT NULL UNIQUE,  scopes TEXT NOT NULL, redirect_uri TEXT DEFAULT 'urn:ietf:wg:oauth:2.0:oob', name TEXT, link TEXT, last_accessed TIMESTAMP);

-- TODO: Separate a user's handle into two components.
-- A username and a domain.
-- Or, do this only if there are any benefits to be gained.

-- id, TEXT PRIMARY KEY NOT NULL: The user ID
-- kind, TEXT NOT NULL: The user type, see UserType object in user.nim
-- handle, TEXT NOT NULL: The user's actual username (Fx. alice@alice.wonderland)
-- domain, TEXT: The domain name that belongs to the user, for local users this is empty but for remote/federated users, this is the domain upon which they reside.
-- name, TEXT DEFAULT 'New User': The user's display name (Fx. Alice)
-- local, BOOLEAN NOT NULL: A boolean indicating whether the user originates from the local server or another one.
-- email, TEXT: The user's email (Empty for remote users)
-- bio, TEXT: The user's biography 
-- password, TEXT: The user's hashed & salted password (Empty for remote users obv)
-- salt, TEXT: The user's salt (Empty for remote users obv)
-- kdf, INTEGER NOT NULL: The version of the key derivation function. See DESIGN.md's Key derivation function TABLE IF NOT EXISTS for more.
-- admin, BOOLEAN NOT NULL DEFAULT FALSE: A boolean indicating whether or not this user is an Admin.
-- moderator, BOOLEAN NOT NULL DEFAULT FALSE: A boolean indicating whether or not this user is a Moderator.
-- discoverable, BOOLEAN NOT NULL DEFAULT TRUE: A boolean indicating whether or not this user is discoverable in frontends
-- is_frozen, BOOLEAN NOT NULL: A boolean indicating whether this user is frozen (Posts from this user will not be stored)
-- is_verified, BOOLEAN NOT NULL: A boolean indicating whether this user's email address has been verified (NOT the same as an approval)
-- is_approved, BOOLEAN NOT NUL: A boolean indicating if the user hs been approved by an administrator
CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, handle TEXT UNIQUE NOT NULL, domain TEXT, name TEXT DEFAULT 'New User', local BOOLEAN NOT NULL, email TEXT, bio TEXT, password TEXT, salt TEXT, kdf INTEGER NOT NULL, admin BOOLEAN NOT NULL DEFAULT FALSE, moderator BOOLEAN NOT NULL DEFAULT FALSE, discoverable BOOLEAN NOT NULL DEFAULT TRUE, is_frozen BOOLEAN NOT NULL, is_verified BOOLEAN NOT NULL, is_approved BOOLEAN NOT NULL);

-- id, TEXT PRIMARY KEY NOT NULL: The Post id
-- recipients, TEXT: A comma-separated list of recipients since postgres arrays are a nightmare.
-- sender, TEXT NOT NULL: A string containing the sender's id
-- replyto, TEXT DEFAULT '': A string containing the post that the sender is replying to, if at all.
-- written, TIMESTAMP NOT NULL: A timestamp containing the date that the post was originally written (and published)
-- modified, BOOLEAN NOT NULL DEFAULT FALSE: A boolean indicating whether the post was modified or not.
-- local, BOOLEAN NOT NULL: A boolean indicating whether the post originated from this server or other servers.
-- client, TEXT NOT NULL DEFAULT '0': The client that sent the post
-- level, smallint NOT NULL DEFAULT 0: The privacy level for the post
CREATE TABLE IF NOT EXISTS posts (id TEXT PRIMARY KEY NOT NULL, recipients TEXT, sender TEXT NOT NULL, replyto TEXT DEFAULT '', written TIMESTAMP NOT NULL, modified BOOLEAN NOT NULL DEFAULT FALSE, local BOOLEAN NOT NULL, client TEXT NOT NULL DEFAULT '0', level smallint NOT NULL DEFAULT 0, foreign key (sender) references users(id),foreign key (client) references apps(id));

-- pid, TEXT PRIMARY KEY NOT NULL: The post ID for the content.
-- kind, smallint NOT NULL DEFAULT 0: The specific kind of content it is
-- cid, TEXT DEFAULT '': The id for the content, if applicable.
CREATE TABLE IF NOT EXISTS posts_content (pid TEXT PRIMARY KEY NOT NULL,kind smallint NOT NULL DEFAULT 0, cid TEXT DEFAULT '', foreign key (pid) references posts(id));

-- pid, TEXT PRIMARY KEY NOT NULL: The post id that the text belongs to
-- content, TEXT NOT NULL: The text content itself
-- format, TEXT: The format for the content.
-- published, TIMESTAMP NOT NULL: The date that this content was published
-- latest, BOOLEAN NOT NULL DEFAULT TRUE: Whether or not this is the latest post
-- foreign key (pid) references posts(id): Some foreign keys for integrity
CREATE TABLE IF NOT EXISTS posts_text (pid TEXT PRIMARY KEY NOT NULL, content TEXT NOT NULL, format TEXT, published TIMESTAMP NOT NULL, latest BOOLEAN NOT NULL DEFAULT TRUE, foreign key (pid) references posts(id) );

-- pid, TEXT NOT NULL: ID of post that the user reacted to
-- uid, TEXT NOT NULL: ID of user who reacted to that post
-- reaction, TEXT NOT NULL: Specific reaction, could be favorite or the shortcode of an emoji.
CREATE TABLE IF NOT EXISTS reactions (pid TEXT NOT NULL, uid TEXT NOT NULL, reaction TEXT NOT NULL, foreign key (pid) references posts(id), foreign key (uid) references users(id));

-- follower, TEXT NOT NULL: ID of user that is following
-- following, TEXT NOT NULL: ID of the user that is being followed
-- approved, BOOLEAN NOT NULL: Whether or not the follow has gone-through, ie. if its approved
CREATE TABLE IF NOT EXISTS follows (follower TEXT NOT NULL,following TEXT NOT NULL,approved BOOLEAN NOT NULL,foreign key (follower) references users(id),foreign key (following) references users(id));

-- name, PRIMARY KEY TEXT NOT NULL: The name of the hashtag itself
-- url, TEXT: An optional URL for the hashtag (dictated by MastoAPI)
-- trendable, BOOLEAN DEFAULT true: Whether or not the hashtag is allowed to trend.
-- usable, BOOLEAN DEFAULT true: Whether or not the hashtag is disabled from auto-linking.
-- requires_review, BOOLEAN DEFAULT false: Whether or not the hashtag has yet been reviewed to approve or deny the trendable attribute.
--
-- Non-MastoAPI columns:
-- description, TEXT: An optional description for the hashtag (Next to url)
-- system, BOOLEAN DEFAULT false: Allows you to specify whether or not the hashtag is a hard requirement.
-- (Ie, it's a required option among others for sending a post, useful for implementing categories in nimforum.)
-- (After requires_review)
CREATE TABLE IF NOT EXISTS tag (name TEXT PRIMARY KEY NOT NULL, url TEXT NOT NULL, description TEXT, trendable BOOLEAN DEFAULT true, usable BOOLEAN DEFAULT true, requires_review BOOLEAN DEFAULT false, system BOOLEAN DEFAULT false);

-- pid, TEXT PRIMARY KEY NOT NULL: The post id that the tag is associated with.
-- tag, TEXT NOT NULL: The hashtag itself
-- sender, TEXT NOT NULL: The sender of the post.
-- use_date, DATE: the time that the hashtag was added
-- foreign key (sender) references users(id)
-- foreign key (pid) references posts(id)
-- foreign key (tag) references tag(name)
CREATE TABLE IF NOT EXISTS posts_tag(pid TEXT PRIMARY KEY NOT NULL, tag TEXT NOT NULL, sender TEXT NOT NULL, use_date DATE, foreign key (sender) references users(id), foreign key (pid) references posts(id), foreign key (tag) references tag(name))

-- follower, TEXT NOT NULL: ID of user that is following
-- following, TEXT NOT NULL: the hashtag being followed
-- foreign key (follower) references users(id)
-- foreign key (following) references tag(name)
CREATE TABLE IF NOT EXISTS tag_follows (follower TEXT NOT NULL,following TEXT NOT NULL,foreign key (follower) references users(id),foreign key (following) references tag(name));

-- pid, TEXT NOT NULL: ID of post that user boosted
-- uid, TEXT NOT NULL: ID of user that boosted post
-- level, smallint NOT NULL DEFAULT 0: The boost level, ie. is it followers-only or whatever. (Same as post privacy level)
CREATE TABLE IF NOT EXISTS boosts (pid TEXT NOT NULL,uid TEXT NOT NULL,level smallint NOT NULL DEFAULT 0,foreign key (pid) references posts(id), foreign key (uid) references users(id));

-- TODO: This is poorly implemented, we don't even store the domain we need to verify...

-- key, TEXT NOT NULL: The key part of the field
-- value, TEXT NOT NULL: The value part of the field.
-- uid, TEXT NOT NULL: Which user has created this profile field
-- verified, BOOLEAN DEFAULT FALSE: A boolean indicating if the profile field has been verified, fx. domain verification and so on.
-- verified_at, TIMESTAMP: A timestamp for when the field was verified
CREATE TABLE IF NOT EXISTS fields (key TEXT NOT NULL, value TEXT NOT NULL, uid TEXT NOT NULL, verified BOOLEAN DEFAULT FALSE, verified_at TIMESTAMP, foreign key (uid) references users(id));

-- id, TEXT PRIMARY KEY UNIQUE NOT NULL: The id for the session, aka. the session token itself
-- uid, TEXT NOT NULL: User ID for the session
-- last_used, TIMESTAMP NOT NULL: When the session was last used.
CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY UNIQUE NOT NULL,uid TEXT NOT NULL,last_used TIMESTAMP NOT NULL,foreign key (uid) references users(id));

-- id TEXT PRIMARY KEY NOT NULL: The code itself (also acts as an id in this case)
-- uid TEXT NOT NULL: The user id associated with this code.
-- cid TEXT NOT NULL: The client id associated with this code.
-- scopes TEXT DEFAULT 'read': The scopes that were requested
CREATE TABLE IF NOT EXISTS auth_codes (id TEXT PRIMARY KEY NOT NULL,uid TEXT NOT NULL,cid TEXT NOT NULL,scopes TEXT DEFAULT 'read',foreign key (cid) references apps(id), foreign key (uid) references users(id));

-- id TEXT PRIMARY KEY NOT NULL UNIQUE: The oauth token
-- uses_code BOOLEAN DEFAULT 'false': The type of token.
-- code TEXT UNIQUE: The oauth code that was generated for this token
-- cid TEXT NOT NULL: The client id of the app that this token belongs to
-- last_use TIMESTAMP NOT NULL: Anything older than a week will be cleared out
CREATE TABLE IF NOT EXISTS oauth (id TEXT PRIMARY KEY NOT NULL UNIQUE, uses_code BOOLEAN DEFAULT 'false', code TEXT UNIQUE, cid TEXT NOT NULL, last_use TIMESTAMP NOT NULL, foreign key (code) references auth_codes(id),foreign key (cid) references apps(id));

-- id TEXT PRIMARY KEY NOT NULL UNIQUE: The email code
-- uid TEXT NOT NULL UNIQUE: The user it belongs to
-- date TIMESTAMP NOT NULL: The date it was created
CREATE TABLE IF NOT EXISTS email_codes (id TEXT PRIMARY KEY NOT NULL UNIQUE,uid TEXT NOT NULL UNIQUE,date TIMESTAMP NOT NULL,foreign key (uid) references users(id));

-- pid TEXT NOT NULL: The post being bookmarked
-- uid TEXT NOT NULL: The user who bookmarked the post
CREATE TABLE IF NOT EXISTS bookmarks (pid TEXT NOT NULL,uid TEXT NOT NULL,foreign key (uid) references users(id), foreign key (pid) references posts(id));

-- id TEXT NOT NULL PRIMARY KEY: The ID for the poll 
-- options TEXT NOT NULL: A comma-separated list of options/answers one can answer
-- expiration_date TIMESTAMP: When the poll will no longer be open to votes
-- multi_choice BOOLEAN NOT NULL DEFAULT FALSE: Whether or not the poll is a multi-choice poll...
CREATE TABLE IF NOT EXISTS polls (id TEXT NOT NULL PRIMARY KEY, options TEXT NOT NULL, expiration_date TIMESTAMP, multi_choice BOOLEAN NOT NULL DEFAULT FALSE );

-- uid TEXT NOT NULL: The user who voted
-- poll_id TEXT NOT NULL: The poll they voted on
-- option TEXT NOT NULL: The option they chose
CREATE TABLE IF NOT EXISTS polls_answer (uid TEXT NOT NULL, poll_id TEXT NOT NULL, option TEXT NOT NULL, foreign key (uid) references users(id),foreign key (poll_id) references polls(id));

-- Add a null user for when users are deleted and we need to re-assign their posts.
INSERT INTO users VALUES ('null', 'Person', 'null', '', 'Deleted User', TRUE, '', '', '', '', 1000, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE) ON CONFLICT DO NOTHING;

-- Make a null app client
INSERT INTO apps VALUES ('0', '0', 'read', '', '', '', '1970-01-01') ON CONFLICT DO NOTHING;

-- Create an index on the post table to speed up post by user searches.
CREATE INDEX IF NOT EXISTS snd_idx ON posts USING btree (sender);