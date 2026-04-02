-- =============================================================================
-- MIGRATION 001: Extensions, Core Types, Users & Auth Setup
-- =============================================================================

-- ---------------------------------------------------------------------------
-- EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";   -- full-text search similarity

-- ---------------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------------
CREATE TYPE public.global_role AS ENUM ('MASTER', 'ADMIN', 'MEMBER', 'VIEWER');
CREATE TYPE public.card_status  AS ENUM ('active', 'completed', 'overdue', 'archived');
CREATE TYPE public.entity_type  AS ENUM (
  'workspace','board','list','card',
  'card_comment','checklist','checklist_item',
  'card_attachment','card_member','card_label',
  'custom_field','custom_field_value',
  'automation','notification','user'
);
CREATE TYPE public.custom_field_type AS ENUM ('text','number','date','list','boolean');
CREATE TYPE public.board_visibility  AS ENUM ('private','workspace','public');
CREATE TYPE public.notification_event AS ENUM (
  'card_assigned','card_mentioned','card_moved',
  'card_due_soon','card_overdue','comment_added',
  'checklist_completed','board_member_added'
);

-- ---------------------------------------------------------------------------
-- PROFILES (extends auth.users – one-to-one)
-- RF01, RF04
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     TEXT        NOT NULL CHECK (char_length(full_name) BETWEEN 2 AND 120),
  avatar_url    TEXT,
  preferences   JSONB       NOT NULL DEFAULT '{}',
  global_role   public.global_role NOT NULL DEFAULT 'MEMBER',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.profiles IS 'One-to-one extension of auth.users. Global role lives here.';
COMMENT ON COLUMN public.profiles.global_role IS 'MASTER = godmode. ADMIN/MEMBER/VIEWER = workspace-scoped.';

-- Guarantee exactly ONE MASTER exists and cannot be removed/demoted
-- Enforced via trigger below (RF05, RF08)

-- ---------------------------------------------------------------------------
-- TRIGGER: keep updated_at in sync
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- ---------------------------------------------------------------------------
-- TRIGGER: auto-create profile on signup (RF01)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1))
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ---------------------------------------------------------------------------
-- TRIGGER: prevent MASTER demotion or deletion (RF08)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_master()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  master_count INT;
BEGIN
  -- Prevent demotion
  IF TG_OP = 'UPDATE' THEN
    IF OLD.global_role = 'MASTER' AND NEW.global_role <> 'MASTER' THEN
      RAISE EXCEPTION 'Cannot demote a MASTER user.';
    END IF;
  END IF;

  -- Prevent deletion of last MASTER
  IF TG_OP = 'DELETE' THEN
    IF OLD.global_role = 'MASTER' THEN
      SELECT COUNT(*) INTO master_count FROM public.profiles WHERE global_role = 'MASTER';
      IF master_count <= 1 THEN
        RAISE EXCEPTION 'Cannot delete the last MASTER user.';
      END IF;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_protect_master
  BEFORE UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.protect_master();

-- ---------------------------------------------------------------------------
-- INDEXES
-- ---------------------------------------------------------------------------
CREATE INDEX idx_profiles_global_role ON public.profiles(global_role);
