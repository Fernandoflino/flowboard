-- =============================================================================
-- MIGRATION 002: Workspaces & Members (Multi-tenant core)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- WORKSPACES (RF10, RF11)
-- ---------------------------------------------------------------------------
CREATE TABLE public.workspaces (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
  description TEXT,
  owner_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.workspaces IS 'Tenant boundary. All data is scoped to a workspace.';

CREATE TRIGGER trg_workspaces_updated_at
  BEFORE UPDATE ON public.workspaces
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- ---------------------------------------------------------------------------
-- WORKSPACE MEMBERS (RF12, RF13)
-- role here is workspace-scoped: ADMIN | MEMBER | VIEWER
-- MASTER is global (stored on profiles.global_role), not here.
-- ---------------------------------------------------------------------------
CREATE TABLE public.workspace_members (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID        NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id      UUID        NOT NULL REFERENCES public.profiles(id)   ON DELETE CASCADE,
  role         public.global_role NOT NULL DEFAULT 'MEMBER'
                           CHECK (role IN ('ADMIN','MEMBER','VIEWER')),
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (workspace_id, user_id)
);

COMMENT ON TABLE public.workspace_members IS
  'Workspace-scoped membership. role ∈ {ADMIN, MEMBER, VIEWER}. '
  'MASTER users bypass this via RLS helper function.';

-- When a workspace is created, automatically add the owner as ADMIN
CREATE OR REPLACE FUNCTION public.handle_workspace_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.workspace_members (workspace_id, user_id, role)
  VALUES (NEW.id, NEW.owner_id, 'ADMIN');
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_workspace_created
  AFTER INSERT ON public.workspaces
  FOR EACH ROW EXECUTE PROCEDURE public.handle_workspace_created();

-- ---------------------------------------------------------------------------
-- RLS HELPER: is current user a member of a given workspace?
-- Used throughout ALL downstream RLS policies.
-- SECURITY DEFINER so it runs with elevated rights but is read-only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_workspace_member(p_workspace_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id          = auth.uid()
      AND global_role = 'MASTER'
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS HELPER: workspace-scoped role for the current user
-- Returns the role string or NULL if not a member (MASTER gets 'MASTER').
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_workspace_role(p_workspace_id UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    CASE
      WHEN p.global_role = 'MASTER' THEN 'MASTER'
      ELSE wm.role::TEXT
    END
  FROM public.profiles p
  LEFT JOIN public.workspace_members wm
    ON wm.workspace_id = p_workspace_id AND wm.user_id = p.id
  WHERE p.id = auth.uid()
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- INDEXES
-- ---------------------------------------------------------------------------
CREATE INDEX idx_workspace_members_user      ON public.workspace_members(user_id);
CREATE INDEX idx_workspace_members_workspace ON public.workspace_members(workspace_id);
