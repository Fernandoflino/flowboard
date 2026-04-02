-- =============================================================================
-- MIGRATION 005: Activity Logs, Notifications, Automations
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ACTIVITY LOGS (RF40, RF41) — CRITICAL
-- Immutable audit trail. No UPDATE/DELETE via RLS.
-- ---------------------------------------------------------------------------
CREATE TABLE public.activity_logs (
  id           UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID              NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  board_id     UUID                       REFERENCES public.boards(id)     ON DELETE SET NULL,
  user_id      UUID              NOT NULL REFERENCES public.profiles(id)   ON DELETE RESTRICT,
  action_type  TEXT              NOT NULL,   -- 'card.created', 'card.moved', etc.
  entity_type  public.entity_type NOT NULL,
  entity_id    UUID              NOT NULL,
  metadata     JSONB             NOT NULL DEFAULT '{}',
  ip_address   INET,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.activity_logs IS
  'Immutable audit trail. RLS blocks UPDATE and DELETE for all roles except MASTER.';

-- Partitioned by month for performance at scale.
-- For simplicity here we use a regular table with a strong index.
CREATE INDEX idx_activity_workspace   ON public.activity_logs(workspace_id, created_at DESC);
CREATE INDEX idx_activity_board       ON public.activity_logs(board_id, created_at DESC)
  WHERE board_id IS NOT NULL;
CREATE INDEX idx_activity_entity      ON public.activity_logs(entity_type, entity_id);
CREATE INDEX idx_activity_user        ON public.activity_logs(user_id, created_at DESC);
CREATE INDEX idx_activity_action      ON public.activity_logs(action_type);
CREATE INDEX idx_activity_created_at  ON public.activity_logs(created_at DESC);

-- ---------------------------------------------------------------------------
-- AUTOMATIC ACTIVITY LOG via triggers (RF41)
-- One generic function; each table gets its own trigger.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_activity(
  p_workspace_id UUID,
  p_board_id     UUID,
  p_user_id      UUID,
  p_action_type  TEXT,
  p_entity_type  public.entity_type,
  p_entity_id    UUID,
  p_metadata     JSONB DEFAULT '{}'
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.activity_logs
    (workspace_id, board_id, user_id, action_type, entity_type, entity_id, metadata)
  VALUES
    (p_workspace_id, p_board_id, p_user_id, p_action_type, p_entity_type, p_entity_id, p_metadata);
END;
$$;

-- Helper: get workspace_id from a card_id (used in triggers)
CREATE OR REPLACE FUNCTION public.get_card_workspace(p_card_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT w.id
  FROM   public.cards c
  JOIN   public.lists l  ON l.id = c.list_id
  JOIN   public.boards b ON b.id = l.board_id
  JOIN   public.workspaces w ON w.id = b.workspace_id
  WHERE  c.id = p_card_id;
$$;

CREATE OR REPLACE FUNCTION public.get_card_board(p_card_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b.id
  FROM   public.cards c
  JOIN   public.lists l  ON l.id = c.list_id
  JOIN   public.boards b ON b.id = l.board_id
  WHERE  c.id = p_card_id;
$$;

-- CARD triggers
CREATE OR REPLACE FUNCTION public.trg_log_card()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_action TEXT;
  v_meta   JSONB;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action := 'card.created';
    v_meta   := jsonb_build_object('title', NEW.title);
    PERFORM public.log_activity(
      public.get_card_workspace(NEW.id), public.get_card_board(NEW.id),
      NEW.created_by, v_action, 'card', NEW.id, v_meta);

  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.list_id <> NEW.list_id THEN
      v_action := 'card.moved';
      v_meta   := jsonb_build_object('from_list', OLD.list_id, 'to_list', NEW.list_id);
    ELSIF OLD.status <> NEW.status THEN
      v_action := 'card.status_changed';
      v_meta   := jsonb_build_object('from', OLD.status, 'to', NEW.status);
    ELSIF OLD.title <> NEW.title OR OLD.description IS DISTINCT FROM NEW.description THEN
      v_action := 'card.updated';
      v_meta   := jsonb_build_object('fields', 'title/description');
    ELSE
      v_action := 'card.updated';
      v_meta   := '{}'::JSONB;
    END IF;
    PERFORM public.log_activity(
      public.get_card_workspace(NEW.id), public.get_card_board(NEW.id),
      auth.uid(), v_action, 'card', NEW.id, v_meta);

  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'card.deleted';
    v_meta   := jsonb_build_object('title', OLD.title);
    PERFORM public.log_activity(
      public.get_card_workspace(OLD.id), public.get_card_board(OLD.id),
      auth.uid(), v_action, 'card', OLD.id, v_meta);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_cards_activity
  AFTER INSERT OR UPDATE OR DELETE ON public.cards
  FOR EACH ROW EXECUTE PROCEDURE public.trg_log_card();

-- COMMENT trigger
CREATE OR REPLACE FUNCTION public.trg_log_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.log_activity(
    public.get_card_workspace(NEW.card_id),
    public.get_card_board(NEW.card_id),
    NEW.user_id, 'comment.added', 'card_comment', NEW.id,
    jsonb_build_object('card_id', NEW.card_id, 'preview', left(NEW.content, 80))
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_card_comments_activity
  AFTER INSERT ON public.card_comments
  FOR EACH ROW EXECUTE PROCEDURE public.trg_log_comment();

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS (RF33)
-- ---------------------------------------------------------------------------
CREATE TABLE public.notifications (
  id           UUID                      PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID                      NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id      UUID                      NOT NULL REFERENCES public.profiles(id)   ON DELETE CASCADE,
  event_type   public.notification_event NOT NULL,
  entity_type  public.entity_type        NOT NULL,
  entity_id    UUID                      NOT NULL,
  actor_id     UUID                                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  payload      JSONB                     NOT NULL DEFAULT '{}',
  is_read      BOOLEAN                   NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ               NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user      ON public.notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_workspace ON public.notifications(workspace_id);

-- ---------------------------------------------------------------------------
-- AUTOMATIONS (RF38)
-- Stores trigger/condition/action definitions; execution is done server-side.
-- ---------------------------------------------------------------------------
CREATE TABLE public.automations (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  board_id     UUID        NOT NULL REFERENCES public.boards(id) ON DELETE CASCADE,
  name         TEXT        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  trigger_def  JSONB       NOT NULL,   -- { event: 'card.moved', conditions: [...] }
  action_def   JSONB       NOT NULL,   -- { type: 'move_card' | 'assign_member' | ..., params: {} }
  created_by   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_automations_updated_at
  BEFORE UPDATE ON public.automations
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX idx_automations_board ON public.automations(board_id, is_active);

-- Automation execution log
CREATE TABLE public.automation_runs (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  automation_id UUID        NOT NULL REFERENCES public.automations(id) ON DELETE CASCADE,
  triggered_by  UUID                    REFERENCES public.profiles(id) ON DELETE SET NULL,
  entity_id     UUID        NOT NULL,
  status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','success','error')),
  error_message TEXT,
  executed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_automation_runs ON public.automation_runs(automation_id, executed_at DESC);
