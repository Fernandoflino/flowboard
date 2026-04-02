-- =============================================================================
-- MIGRATION 003: Boards, Lists & Cards
-- =============================================================================

-- ---------------------------------------------------------------------------
-- BOARDS (RF14, RF15)
-- ---------------------------------------------------------------------------
CREATE TABLE public.boards (
  id            UUID                    PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id  UUID                    NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  name          TEXT                    NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
  description   TEXT,
  visibility    public.board_visibility NOT NULL DEFAULT 'workspace',
  background    JSONB,          -- { type: 'color'|'image', value: '#...' | 'url' }
  is_archived   BOOLEAN                 NOT NULL DEFAULT FALSE,
  created_by    UUID                    NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at    TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_boards_updated_at
  BEFORE UPDATE ON public.boards
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_boards_workspace ON public.boards(workspace_id);
CREATE INDEX idx_boards_created_by ON public.boards(created_by);

-- ---------------------------------------------------------------------------
-- LISTS (RF16, RF17)
-- position uses FLOAT to allow insertion between items without mass-update.
-- ---------------------------------------------------------------------------
CREATE TABLE public.lists (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  board_id    UUID        NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  name        TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
  position    FLOAT       NOT NULL DEFAULT 0,
  is_archived BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_lists_updated_at
  BEFORE UPDATE ON public.lists
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_lists_board ON public.lists(board_id, position);

-- ---------------------------------------------------------------------------
-- CARDS (RF18–RF21, RF27)
-- ---------------------------------------------------------------------------
CREATE TABLE public.cards (
  id              UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  list_id         UUID              NOT NULL REFERENCES public.lists(id)    ON DELETE CASCADE,
  title           TEXT              NOT NULL CHECK (char_length(title) BETWEEN 1 AND 500),
  description     TEXT,
  position        FLOAT             NOT NULL DEFAULT 0,
  status          public.card_status NOT NULL DEFAULT 'active',
  cover_color     TEXT,             -- hex color
  cover_image_url TEXT,             -- storage URL
  start_date      TIMESTAMPTZ,
  due_date        TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  is_archived     BOOLEAN           NOT NULL DEFAULT FALSE,
  created_by      UUID              NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at      TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_cards_updated_at
  BEFORE UPDATE ON public.cards
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- Auto-set completed_at when status flips to 'completed'
CREATE OR REPLACE FUNCTION public.handle_card_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
    NEW.completed_at := NOW();
  END IF;
  IF NEW.status <> 'completed' THEN
    NEW.completed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_card_status_change
  BEFORE UPDATE ON public.cards
  FOR EACH ROW EXECUTE PROCEDURE public.handle_card_status_change();

-- Auto-mark overdue cards (called by a scheduled function or on read)
-- We also compute overdue dynamically in views/reports.

CREATE INDEX idx_cards_list          ON public.cards(list_id, position);
CREATE INDEX idx_cards_status        ON public.cards(status);
CREATE INDEX idx_cards_due_date      ON public.cards(due_date) WHERE due_date IS NOT NULL;
CREATE INDEX idx_cards_created_by    ON public.cards(created_by);

-- Full-text search index on cards (RF34)
CREATE INDEX idx_cards_fts ON public.cards
  USING gin(to_tsvector('portuguese', coalesce(title,'') || ' ' || coalesce(description,'')));

-- ---------------------------------------------------------------------------
-- CARD MEMBERS (RF21)
-- ---------------------------------------------------------------------------
CREATE TABLE public.card_members (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id    UUID        NOT NULL REFERENCES public.cards(id)    ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  added_by   UUID                    REFERENCES public.profiles(id) ON DELETE SET NULL,
  added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (card_id, user_id)
);

CREATE INDEX idx_card_members_card ON public.card_members(card_id);
CREATE INDEX idx_card_members_user ON public.card_members(user_id);
