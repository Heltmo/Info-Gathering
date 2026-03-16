-- ═══════════════════════════════════════════════════════════════
-- BRIM COMMUNITY — Supabase SQL Schema
-- Run this entire file in Supabase → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════

-- ── 1. EXTEND members TABLE ──────────────────────────────────────
ALTER TABLE members ADD COLUMN IF NOT EXISTS user_id   UUID    REFERENCES auth.users(id);
ALTER TABLE members ADD COLUMN IF NOT EXISTS role      TEXT    NOT NULL DEFAULT 'member';
ALTER TABLE members ADD COLUMN IF NOT EXISTS xp        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE members ADD COLUMN IF NOT EXISTS level_id  INTEGER NOT NULL DEFAULT 1;
ALTER TABLE members ADD COLUMN IF NOT EXISTS verified  BOOLEAN NOT NULL DEFAULT false;

-- ── 2. LEVELS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS levels (
  id          SERIAL  PRIMARY KEY,
  name        TEXT    NOT NULL,
  required_xp INTEGER NOT NULL DEFAULT 0
);

INSERT INTO levels (id, name, required_xp) VALUES
  (1, 'Nykommer',              0),
  (2, 'Vokter',              100),
  (3, 'Kjemper',             300),
  (4, 'Mester',              700),
  (5, 'Eldervokter',        1500),
  (6, 'Legende',            3000),
  (7, 'Den Syvende Flamme', 6000)
ON CONFLICT (id) DO NOTHING;

-- ── 3. COMMUNITY POSTS ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_posts (
  id          SERIAL      PRIMARY KEY,
  author_id   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name TEXT,
  content     TEXT        NOT NULL,
  type        TEXT        NOT NULL DEFAULT 'post',   -- 'post' | 'system' | 'welcome'
  parent_id   INTEGER     REFERENCES community_posts(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure comment-parent column exists for existing deployments
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS parent_id INTEGER REFERENCES community_posts(id) ON DELETE CASCADE;

-- ── MEMBERS extras
ALTER TABLE members ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- ── COMMUNITY POSTS extras
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT false;

-- ── EVENT PROPOSALS extras
ALTER TABLE event_proposals ADD COLUMN IF NOT EXISTS admin_note TEXT;

-- ── 4. TOURNAMENTS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tournaments (
  id           SERIAL      PRIMARY KEY,
  title        TEXT        NOT NULL,
  description  TEXT,
  status       TEXT        NOT NULL DEFAULT 'upcoming', -- 'upcoming' | 'active' | 'completed' | 'pending' | 'under_review' | 'rejected'
  start_date   DATE,
  end_date     DATE,
  location     TEXT,
  suggested_by UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add columns for existing deployments
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS location     TEXT;
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS suggested_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- ── 5. TOURNAMENT PARTICIPANTS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS tournament_participants (
  id            SERIAL      PRIMARY KEY,
  tournament_id INTEGER     NOT NULL REFERENCES tournaments(id)  ON DELETE CASCADE,
  user_id       UUID        NOT NULL REFERENCES auth.users(id)   ON DELETE CASCADE,
  member_name   TEXT,
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(tournament_id, user_id)
);

-- ── 6. TOURNAMENT RESULTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tournament_results (
  id            SERIAL      PRIMARY KEY,
  tournament_id INTEGER     NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  winner_id     UUID        REFERENCES auth.users(id)           ON DELETE SET NULL,
  winner_name   TEXT        NOT NULL,
  position      INTEGER     NOT NULL DEFAULT 1,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 7. ANNOUNCEMENTS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS announcements (
  id         SERIAL      PRIMARY KEY,
  title      TEXT        NOT NULL,
  content    TEXT,
  type       TEXT        NOT NULL DEFAULT 'info',  -- 'info' | 'warning' | 'event'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════

-- members
ALTER TABLE members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "members_select" ON members;
DROP POLICY IF EXISTS "members_insert" ON members;
DROP POLICY IF EXISTS "members_update" ON members;
CREATE POLICY "members_select" ON members FOR SELECT TO authenticated USING (true);
CREATE POLICY "members_insert" ON members FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "members_update" ON members FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- Also allow anon to read count (for the public counter)
DROP POLICY IF EXISTS "members_anon_select" ON members;
CREATE POLICY "members_anon_select" ON members FOR SELECT TO anon USING (true);

-- community_posts
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "posts_select" ON community_posts;
DROP POLICY IF EXISTS "posts_insert" ON community_posts;
DROP POLICY IF EXISTS "posts_delete" ON community_posts;
CREATE POLICY "posts_select" ON community_posts FOR SELECT TO authenticated USING (true);
CREATE POLICY "posts_insert" ON community_posts FOR INSERT TO authenticated WITH CHECK (author_id IS NULL OR auth.uid() = author_id);
CREATE POLICY "posts_delete" ON community_posts FOR DELETE TO authenticated USING (auth.uid() = author_id);

-- likes for community posts
CREATE TABLE IF NOT EXISTS community_post_likes (
  id       SERIAL PRIMARY KEY,
  post_id  INTEGER NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id  UUID    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

ALTER TABLE community_post_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "likes_select" ON community_post_likes;
DROP POLICY IF EXISTS "likes_insert" ON community_post_likes;
DROP POLICY IF EXISTS "likes_delete" ON community_post_likes;
CREATE POLICY "likes_select" ON community_post_likes FOR SELECT TO authenticated USING (true);
CREATE POLICY "likes_insert" ON community_post_likes FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "likes_delete" ON community_post_likes FOR DELETE TO authenticated USING (user_id = auth.uid());

-- tournaments (public read, admin write handled in app)
ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tournaments_select" ON tournaments;
CREATE POLICY "tournaments_select" ON tournaments FOR SELECT USING (true);
CREATE POLICY "tournaments_insert" ON tournaments FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "tournaments_update" ON tournaments FOR UPDATE TO authenticated USING (true);

-- tournament_participants
ALTER TABLE tournament_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tp_select" ON tournament_participants;
DROP POLICY IF EXISTS "tp_insert" ON tournament_participants;
DROP POLICY IF EXISTS "tp_delete" ON tournament_participants;
CREATE POLICY "tp_select"  ON tournament_participants FOR SELECT TO authenticated USING (true);
CREATE POLICY "tp_insert"  ON tournament_participants FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "tp_delete"  ON tournament_participants FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- tournament_results
ALTER TABLE tournament_results ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tr_select" ON tournament_results;
CREATE POLICY "tr_select" ON tournament_results FOR SELECT USING (true);
CREATE POLICY "tr_insert" ON tournament_results FOR INSERT TO authenticated WITH CHECK (true);

-- announcements
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ann_select" ON announcements;
CREATE POLICY "ann_select" ON announcements FOR SELECT USING (true);
CREATE POLICY "ann_insert" ON announcements FOR INSERT TO authenticated WITH CHECK (true);

-- ── EVENT PROPOSALS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS event_proposals (
  id          SERIAL      PRIMARY KEY,
  member_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title       TEXT        NOT NULL,
  description TEXT,
  location    TEXT,
  event_date  DATE,
  status      TEXT        NOT NULL DEFAULT 'pending', -- 'pending' | 'under_review' | 'approved' | 'rejected'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE event_proposals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ep_select"       ON event_proposals;
DROP POLICY IF EXISTS "ep_insert"       ON event_proposals;
DROP POLICY IF EXISTS "ep_admin_select" ON event_proposals;
DROP POLICY IF EXISTS "ep_admin_update" ON event_proposals;
-- Members can read their own proposals; admins can read all
CREATE POLICY "ep_select" ON event_proposals FOR SELECT TO authenticated
  USING (
    member_id = (SELECT id FROM members WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin')
  );
-- Members can only insert rows tied to their own members.id
CREATE POLICY "ep_insert" ON event_proposals FOR INSERT TO authenticated
  WITH CHECK (
    member_id = (SELECT id FROM members WHERE user_id = auth.uid())
  );
-- Admins can update status
CREATE POLICY "ep_admin_update" ON event_proposals FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin')
  );

-- levels
ALTER TABLE levels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "levels_select" ON levels;
CREATE POLICY "levels_select" ON levels FOR SELECT USING (true);

-- chat (conversations, members, messages)
CREATE TABLE IF NOT EXISTS conversations (
  id          SERIAL      PRIMARY KEY,
  type        TEXT        NOT NULL DEFAULT 'direct',  -- 'direct' | 'group'
  name        TEXT,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_members (
  id              SERIAL      PRIMARY KEY,
  conversation_id INTEGER     NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
  id              SERIAL      PRIMARY KEY,
  conversation_id INTEGER     NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  author_id       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  author_name     TEXT,
  content         TEXT        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- conversation RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversations_select" ON conversations;
DROP POLICY IF EXISTS "conversations_insert" ON conversations;
CREATE POLICY "conversations_select" ON conversations FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_members.conversation_id = conversations.id
      AND conversation_members.user_id = auth.uid()
  ));
CREATE POLICY "conversations_insert" ON conversations FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

ALTER TABLE conversation_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conv_members_select" ON conversation_members;
DROP POLICY IF EXISTS "conv_members_insert" ON conversation_members;
CREATE POLICY "conv_members_select" ON conversation_members FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "conv_members_insert" ON conversation_members FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM conversations
      WHERE conversations.id = conversation_members.conversation_id
        AND conversations.created_by = auth.uid()
    )
  );

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "messages_select" ON messages;
DROP POLICY IF EXISTS "messages_insert" ON messages;
CREATE POLICY "messages_select" ON messages FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM conversation_members
    WHERE conversation_members.conversation_id = messages.conversation_id
      AND conversation_members.user_id = auth.uid()
  ));
CREATE POLICY "messages_insert" ON messages FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid());
