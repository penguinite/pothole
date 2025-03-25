-- UTF-8 is best.
SET client_encoding = 'UTF8';

-- Needed to work around https://github.com/nim-lang/db_connector/issues/19
-- Without this, it might be possible to do SQL injection.
-- TODO: Fix this in the db_connector library so that everyone can enjoy injection-free data operations.
SET standard_conforming_strings = on;

-- The meta table is used to store metadata about the pothole database itself.
-- It may be used to track schema versions.
CREATE TABLE IF NOT EXISTS meta (k TEXT, v TEXT);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kdf smallint NOT NULL DEFAULT 0, -- See KDF file in docs/db/ folder
    role smallint[] NOT NULL DEFAULT 0, -- See Roles file in docs/db/ folder
    discoverable BOOLEAN NOT NULL DEFAULT false, -- Whether user should be listed publicly or not.
    email_verified BOOLEAN NOT NULL DEFAULT false,
    handle TEXT UNIQUE NOT NULL, -- The "username"
    domain TEXT, -- Domain name of a remote user, null for local users
    display TEXT DEFAULT 'New User', -- Display name
    email TEXT,
    bio TEXT, -- Plain-text only. with emoji support.
    pass TEXT, -- Password hash
    -- This is a base64 string consisting of 20 chars
    salt TEXT, 
);

-- An app is sort of like a session, but for programs.
CREATE TABLE IF NOT EXISTS apps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- client_id
    scopes TEXT[] DEFAULT '{read}',
    redirect_uris TEXT[] DEFAULT '{urn:ietf:wg:oauth:2.0:oob}',
    app_secret TEXT UNIQUE, -- client_secret
    app_name TEXT,
    link TEXT
);

CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender UUID NOT NULL,
    replyto UUID,
    client UUID,
    created TIMESTAMP NOT NULL,
    privacy_level smallint NOT NULL DEFAULT 0,
    is_local BOOLEAN NOT NULL,
    recipients TEXT[], -- list of user IDs mentioned
    tags TEXT[], -- Set of hashtags used in current version of post.
    foreign key (sender) references users(id),
    foreign key (replyto) references posts(id),
    foreign key (client) references apps(id)
);

-- This table stores not just current versions of posts but also
-- past versions and it includes info on when every single one was
-- published.
CREATE TABLE IF NOT EXISTS post_texts (
    pid UUID PRIMARY KEY NOT NULL,
    published TIMESTAMP,
    format smallint NOT NULL DEFAULT 0, -- See "Formats" file in docs/db/ for more info
    content TEXT,
    foreign key (pid) references posts(id)
);

-- Allows for embedding content other than text and tags into posts.
-- Fx. to insert a poll, you'd assign polls a special number (let's say 10)
-- And insert the poll ID, along with the post ID and that special number
-- into this table.
CREATE TABLE IF NOT EXISTS post_embeds (
    pid UUID PRIMARY KEY NOT NULL,
    kind smallint NOT NULL,
    cid UUID,
    foreign key (pid) references posts(id)
);

-- A reaction acts as a sort of like
-- (or favorite if you're into mastodon parlance.)
--
-- In pothole however, these are more general so they can
-- store all sorts of things.
CREATE TABLE IF NOT EXISTS reactions (
    pid UUID NOT NULL, -- Stands for Post ID
    uid UUID NOT NULL, -- Stands for User ID
    reaction TEXT NOT NULL, -- Specific reaction used. Can be anything
    foreign key (pid) references posts(id),
    foreign key (uid) references users(id)
);

-- A boost is a sort of re-tweet, it's a way of sharing a message to a group.
-- And yes, "quote boosts" are just posts with a link at the bottom.
-- They're not true boosts.
CREATE TABLE IF NOT EXISTS boosts (
    pid UUID NOT NULL, -- Stands for Post ID
    uid UUID NOT NULL, -- Stands for User ID
    -- This is similar to privacy_level in the posts table.
    level smallint NOT NULL DEFAULT 0,
    foreign key (pid) references posts(id),
    foreign key (uid) references users(id)
);

-- Stores information about any given hashtag
CREATE TABLE IF NOT EXISTS tag (
    -- Is tag allowed to show up on trending tab
    trendable BOOLEAN DEFAULT true, 
    -- Can this tag automatically be linked in a post?
    usable BOOLEAN DEFAULT true, 
    -- Does this tag require a review by an admin?
    requires_review BOOLEAN DEFAULT false,
    -- Whether a user is **required** to use this tag or other system tags on a post.
    -- This is required for implementing "post categories"
    -- (Think of discord channels or forum categories)
    system BOOLEAN DEFAULT false, 
    name TEXT PRIMARY KEY NOT NULL,
    url TEXT NOT NULL,
    description TEXT
);

-- Simple key-value pairs to be displayed on a user profile.
-- Also, these can be
CREATE TABLE IF NOT EXISTS fields (
    uid UUID PRIMARY KEY NOT NULL,
    -- We will check if a field is verified before it is inserted.
    -- And we will provide an API route to re-check that a field is verified.
    -- Field verification is used to connect a website and a profile together.
    -- This functionality is required by the Mastodon API.
    verified BOOLEAN,
    verified_at TIMESTAMP,
    key TEXT, -- Doesn't matter for verification
    -- If this is an URL, we will connect to it,
    -- parse the HTML and check if a valid link tag exists
    -- to connect the profile and URL together.
    -- To me, this sounds like a possible security vector.
    -- So I'll include a config option to turn it off.
    val TEXT, 
    foreign key (uid) references users(id)
);

-- For users to bookmark a post.
-- TODO: Introduce a third column that can be named by a user.
-- So that they can have different "bookmark categories"
-- (Only if you want to)
CREATE TABLE bookmarks (
    pid UUID NOT NULL, -- Stands for post ID
    uid UUID NOT NULL, -- Stands for user ID
    foreign key (uid) references users(id),
    foreign key (pid) references posts(id)
);

-- TODO: This poll implementation seems a bit too inefficient
-- I dunno, maybe look into it in the future.
CREATE TABLE IF NOT EXISTS polls (
    id UUID PRIMARY KEY NOT NULL,
    pid UUID NOT NULL, -- Associated post.
    options TEXT[] NOT NULL,
    starts TIMESTAMP,
    ends TIMESTAMP,
    multi_choice BOOLEAN DEFAULT FALSE,
    foreign key (pid) references posts(id),
);

CREATE TABLE IF NOT EXISTS poll_votes (
    poll_id UUID NOT NULL, 
    uid UUID NOT NULL,
    option TEXT NOT NULL, -- Specific option voted for
    foreign key (uid) references users(id),
    foreign key (poll_id) references polls(id)
);

-- TODO: Find out if its possible to merge this table
-- with the oauth table.
CREATE TABLE IF NOT EXISTS logins (
    -- Session IDs are generated using the `rng` library
    -- with at least 30 base64 characters.
    -- This gives us average entropy of around ~150
    -- The minimum is 128 bits of entropy.
    -- PS: We can always increase the length later!
    id TEXT PRIMARY KEY UNIQUE NOT NULL,
    uid UUID NOT NULL,
    -- When the session has last been used for a week
    -- We will delete it from the db.
    last_used TIMESTAMP NOT NULL,
    foreign key (uid) references users(id)
);

-- For authenticating users and apps
-- Auth codes are to be deleted after a day or as soon as an app is verified.
CREATE TABLE IF NOT EXISTS auth_codes (
    -- Auth codes are generated same as session IDs
    id TEXT PRIMARY UNIQUE KEY NOT NULL, -- The code itself
    uid UUID NOT NULL, -- Stands for user ID
    cid UUID NOT NULL, -- Stands for client ID
    scopes TEXT[] DEFAULT '{read}',
    -- Auth codes are to be deleted after a day, no matter what.
    -- Alternatively, we could encourage users to setup a daily cron job
    -- with harmless db cleaning commands in potholectl.
    date TIMESTAMP DEFAULT NOW(),
    foreign key (cid) references apps(id),
    foreign key (uid) references users(id)
);

-- For storing email verification codes of users
-- Email codes are to be deleted after a day or as soon as an user is verified.
CREATE TABLE IF NOT EXISTS email_codes (
    -- Email codes are generated same as session IDs
    id TEXT PRIMARY KEY NOT NULL UNIQUE, -- The code itself
    -- Each user can only have a single email code.
    uid UUID NOT NULL UNIQUE,
    -- Email codes are to be deleted after a day, no matter what.
    -- Alternatively, we could encourage users to setup a daily cron job
    -- for harmless db cleaning activities.
    date TIMESTAMP DEFAULT NOW(),
    foreign key (uid) references users(id)
);

CREATE TABLE IF NOT EXISTS oauth_tokens (
    -- OAuth tokens are generated same way as session IDs
    -- Yes, I understand that TEXT is not exactly the best datatype for a primary key.
    -- And UUIDv4 (which gen_random_uuid() generates) are completely random
    -- But I didn't want to sacrifice security, UUIDs seemed too limited for me.
    id TEXT PRIMARY UNIQUE KEY NOT NULL, -- The token itself
    cid UUID,
    -- An app might not be associated with a user, 
    -- in which case, This column is null.
    uid UUID, 
    -- The permissions of a specific token.
    -- An app is allowed to have multiple scopes
    -- And it is allowed to have multiple tokens with each
    -- a sub-scope. (For fine control of permissions)
    -- This is an important security feature.
    scopes TEXT[] DEFAULT '{read}',
    foreign key (cid) references apps(id),
    foreign key (uid) references users(id)
);

-- For users to follow other users
CREATE TABLE IF NOT EXISTS user_follows (
    follower UUID NOT NULL,
    following UUID NOT NULL,
    approved BOOLEAN NOT NULL,
    foreign key (follower) references users(id),
    foreign key (following) references users(id)
);

-- For users to follow hashtags
CREATE TABLE IF NOT EXISTS tag_follows (
    follower UUID NOT NULL,
    following TEXT NOT NULL,
    foreign key (follower) references users(id),
    foreign key (following) references tag(name)
);

-- Add a null user for when users are deleted and we need to re-assign their posts.
INSERT INTO users VALUES ('null', 'Person', 'null', '', 'Deleted User', TRUE, '', '', '', '', 1000, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE) ON CONFLICT DO NOTHING;

-- Make a null app client
-- INSERT INTO apps VALUES ('0', '0', 'read', '', '', '', '1970-01-01') ON CONFLICT DO NOTHING;

-- Create an index on the post table to speed up post by user searches.
--CREATE INDEX IF NOT EXISTS snd_idx ON posts USING btree (sender);