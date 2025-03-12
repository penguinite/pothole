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
    domain TEXT, -- Domain name of a remote user, empty for local users
    display TEXT DEFAULT 'New User', -- Display name
    email TEXT,
    bio TEXT, -- Plain-text only. with emoji support.
    pass TEXT, -- Password
    salt TEXT,
);

-- An app is sort of like a session, but for programs.
CREATE TABLE IF NOT EXISTS apps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), -- client_id
    last_accessed TIMESTAMP, -- Deleted when app hasn't been used for a week
    app_name TEXT,
    app_secret TEXT UNIQUE, -- client_secret
    scopes TEXT[] DEFAULT '{read}',
    redirect_uris TEXT[] DEFAULT '{urn:ietf:wg:oauth:2.0:oob}',
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
CREATE TABLE IF NOT EXISTS posts_text (
    pid UUID PRIMARY KEY NOT NULL,
    published TIMESTAMP,
    format smallint NOT NULL DEFAULT 0, -- See "Formats" file in docs/db/ for more info
    content TEXT,
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

-- For users to follow other users
CREATE TABLE IF NOT EXISTS user_follows (
    follower UUID NOT NULL,
    following TEXT NOT NULL,
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


