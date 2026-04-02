-- =============================================================================
-- MIGRATION 004: Card Details
-- Comments, Checklists, Labels, Attachments, Custom Fields
-- =============================================================================

-- ---------------------------------------------------------------------------
-- COMMENTS (RF22)
-- ---------------------------------------------------------------------------
CREATE TABLE public.card_comments (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id    UUID        NOT NULL REFERENCES public.cards(id)    ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  content    TEXT        NOT NULL CHECK (char_length(content) BETWEEN 1 AND 10000),
  is_edited  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_card_comments_updated_at
  BEFORE UPDATE ON public.card_comments
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_card_comments_card ON public.card_comments(card_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- CHECKLISTS (RF23)
-- ---------------------------------------------------------------------------
CREATE TABLE public.checklists (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id    UUID        NOT NULL REFERENCES public.cards(id) ON DELETE CASCADE,
  title      TEXT        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  position   FLOAT       NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_checklists_updated_at
  BEFORE UPDATE ON public.checklists
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_checklists_card ON public.checklists(card_id, position);

-- ---------------------------------------------------------------------------
-- CHECKLIST ITEMS (RF24)
-- ---------------------------------------------------------------------------
CREATE TABLE public.checklist_items (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  checklist_id UUID        NOT NULL REFERENCES public.checklists(id) ON DELETE CASCADE,
  title        TEXT        NOT NULL CHECK (char_length(title) BETWEEN 1 AND 500),
  is_done      BOOLEAN     NOT NULL DEFAULT FALSE,
  position     FLOAT       NOT NULL DEFAULT 0,
  due_date     TIMESTAMPTZ,
  assigned_to  UUID                  REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_checklist_items_updated_at
  BEFORE UPDATE ON public.checklist_items
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_checklist_items_checklist ON public.checklist_items(checklist_id, position);

-- ---------------------------------------------------------------------------
-- LABELS (RF26)
-- Labels belong to a board; cards reference them via N:N
-- ---------------------------------------------------------------------------
CREATE TABLE public.labels (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  board_id   UUID        NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  name       TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  color      TEXT        NOT NULL DEFAULT '#6B7280', -- hex
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (board_id, name)
);

CREATE INDEX idx_labels_board ON public.labels(board_id);

-- CARD ↔ LABEL (N:N)
CREATE TABLE public.card_labels (
  card_id    UUID NOT NULL REFERENCES public.cards(id)  ON DELETE CASCADE,
  label_id   UUID NOT NULL REFERENCES public.labels(id) ON DELETE CASCADE,
  PRIMARY KEY (card_id, label_id)
);

CREATE INDEX idx_card_labels_card  ON public.card_labels(card_id);
CREATE INDEX idx_card_labels_label ON public.card_labels(label_id);

-- ---------------------------------------------------------------------------
-- ATTACHMENTS (RF28–RF30)
-- ---------------------------------------------------------------------------
CREATE TABLE public.card_attachments (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id      UUID        NOT NULL REFERENCES public.cards(id)    ON DELETE CASCADE,
  uploaded_by  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  name         TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 255),
  url          TEXT        NOT NULL,
  storage_path TEXT,           -- internal Supabase Storage path
  mime_type    TEXT,
  size_bytes   BIGINT,
  is_image     BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_card_attachments_card ON public.card_attachments(card_id);

-- ---------------------------------------------------------------------------
-- CUSTOM FIELD DEFINITIONS (RF36, RF37)
-- Defined per board
-- ---------------------------------------------------------------------------
CREATE TABLE public.custom_fields (
  id          UUID                    PRIMARY KEY DEFAULT uuid_generate_v4(),
  board_id    UUID                    NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  name        TEXT                    NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  field_type  public.custom_field_type NOT NULL,
  options     JSONB,          -- for 'list' type: ["option1","option2",...]
  is_required BOOLEAN         NOT NULL DEFAULT FALSE,
  position    FLOAT           NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  UNIQUE (board_id, name)
);

CREATE INDEX idx_custom_fields_board ON public.custom_fields(board_id);

-- ---------------------------------------------------------------------------
-- CUSTOM FIELD VALUES (RF36)
-- One row per card per field
-- ---------------------------------------------------------------------------
CREATE TABLE public.custom_field_values (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  card_id         UUID        NOT NULL REFERENCES public.cards(id)         ON DELETE CASCADE,
  custom_field_id UUID        NOT NULL REFERENCES public.custom_fields(id) ON DELETE CASCADE,
  value_text      TEXT,
  value_number    NUMERIC,
  value_date      TIMESTAMPTZ,
  value_boolean   BOOLEAN,
  value_list      TEXT,       -- selected option from list
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (card_id, custom_field_id)
);

CREATE INDEX idx_cfv_card  ON public.custom_field_values(card_id);
CREATE INDEX idx_cfv_field ON public.custom_field_values(custom_field_id);
