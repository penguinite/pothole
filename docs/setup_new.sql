-- UTF-8 is best.
SET client_encoding = 'UTF8';

-- Needed to work around https://github.com/nim-lang/db_connector/issues/19
-- Without this, it might be possible to do SQL injection.
-- TODO: Fix this in the db_connector library so that everyone can enjoy injection-free data operations.
SET standard_conforming_strings = on;

-- A "kind" is a bit like a role.
CREATE TABLE IF NOT EXISTS kinds (
    id smallint PRIMARY KEY UNIQUE,
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    handle TEXT UNIQUE NOT NULL, -- The "username"
    domain TEXT, -- Domain name of a remote user, empty for local users
    display TEXT DEFAULT 'New User', -- Display name
    email TEXT,
    bio TEXT, -- Plain-text only. with emoji support.
    pass TEXT, -- Password
    salt TEXT,
    kdf smallint NOT NULL DEFAULT 0, -- See KDF file in docs/db/ folder
    kind smallint NOT NULL DEFAULT 0, -- See Roles file in docs/db/ folder (or bottom of this file)
    discoverable BOOLEAN NOT NULL DEFAULT false, -- Whether user should be listed publicly or not.
    email_verified BOOLEAN NOT NULL DEFAULT false
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

-- id, TEXT PRIMARY KEY NOT NULL: The Post id
-- recipients, TEXT: A comma-separated list of recipients since postgres arrays are a nightmare.
-- sender, TEXT NOT NULL: A string containing the sender's id
-- replyto, TEXT DEFAULT '': A string containing the post that the sender is replying to, if at all.
-- written, TIMESTAMP NOT NULL: A timestamp containing the date that the post was originally written (and published)
-- modified, BOOLEAN NOT NULL DEFAULT FALSE: A boolean indicating whether the post was modified or not.
-- local, BOOLEAN NOT NULL: A boolean indicating whether the post originated from this server or other servers.
-- client, TEXT NOT NULL DEFAULT '0': The client that sent the post
-- level, smallint NOT NULL DEFAULT 0: The privacy level for the post
CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipients TEXT, -- Space-separated list of recipients
    sender TEXT NOT NULL, -- 
    replyto TEXT,
    created TIMESTAMP NOT NULL,
    modified BOOLEAN NOT NULL DEFAULT FALSE,
    client TEXT NOT NULL DEFAULT '0',
    is_local BOOLEAN NOT NULL,
    privacy_level smallint NOT NULL DEFAULT 0,
    foreign key (sender) references users(id),
    foreign key (client) references apps(id)
);



-- Default roles:
-- Frozen user role, user is not allowed to do anything.
INSERT INTO kinds VALUES (-1) ON CONFLICT DO NOTHING;

-- Regular unapproved user role, user is allowed to do anything
-- (as long as instance doesn't enable require_approval)
INSERT INTO kinds VALUES (0) ON CONFLICT DO NOTHING;

-- Approved user role, user is allowed to do anything
INSERT INTO kinds VALUES (1) ON CONFLICT DO NOTHING;

-- Moderator role, user is allowed to freeze users
INSERT INTO kinds VALUES (2) ON CONFLICT DO NOTHING;

-- Administrator role, user is allowed to change roles of other users (no limits).
INSERT INTO kinds VALUES (3) ON CONFLICT DO NOTHING;

