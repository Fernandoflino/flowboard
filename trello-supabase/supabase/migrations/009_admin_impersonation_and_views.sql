-- =============================================================================
-- MIGRATION 009: Admin User Management Requests + Impersonation + RF39 helpers
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RF06: MASTER user-management command queue
-- (executed by secure server-side worker/Edge Function with SERVICE_ROLE_KEY)
-- ---------------------------------------------------------------------------
CREATE TABLE public.admin_user_actions (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  requested_by    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  action          TEXT        NOT NULL CHECK (action IN ('create','update','delete','reset_password')),
  target_user_id  UUID                 REFERENCES public.profiles(id) ON DELETE SET NULL,
  target_email    TEXT,
  payload         JSONB       NOT NULL DEFAULT '{}',
  status          TEXT        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','processing','done','failed')),
  error_message   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at    TIMESTAMPTZ
);

CREATE INDEX idx_admin_user_actions_status ON public.admin_user_actions(status, created_at);
CREATE INDEX idx_admin_user_actions_by     ON public.admin_user_actions(requested_by, created_at DESC);

-- Only MASTER can enqueue admin actions.
CREATE OR REPLACE FUNCTION public.request_user_action(
  p_action         TEXT,
  p_target_user_id UUID DEFAULT NULL,
  p_target_email   TEXT DEFAULT NULL,
  p_payload        JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid() AND p.global_role = 'MASTER'
  ) THEN
    RAISE EXCEPTION 'Only MASTER can request user administration actions';
  END IF;

  IF p_action NOT IN ('create','update','delete','reset_password') THEN
    RAISE EXCEPTION 'Invalid action: %', p_action;
  END IF;

  INSERT INTO public.admin_user_actions (
    requested_by, action, target_user_id, target_email, payload
  ) VALUES (
    auth.uid(), p_action, p_target_user_id, lower(trim(p_target_email)), COALESCE(p_payload, '{}'::JSONB)
  )
  RETURNING id INTO v_id;

  PERFORM public.log_activity(
    COALESCE((p_payload->>'workspace_id')::UUID,
      (SELECT wm.workspace_id FROM public.workspace_members wm WHERE wm.user_id = auth.uid() LIMIT 1)
    ),
    NULL,
    auth.uid(),
    'user.admin_action_requested',
    'user',
    COALESCE(p_target_user_id, auth.uid()),
    jsonb_build_object('action', p_action, 'target_email', p_target_email, 'queue_id', v_id)
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.request_user_action(TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_user_action(TEXT, UUID, TEXT, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- RF09: Admin impersonation sessions (fully auditable)
-- ---------------------------------------------------------------------------
CREATE TABLE public.impersonation_sessions (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_user_id   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  target_user_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  workspace_id    UUID                 REFERENCES public.workspaces(id) ON DELETE CASCADE,
  reason          TEXT        NOT NULL CHECK (char_length(reason) BETWEEN 8 AND 1000),
  token           UUID        NOT NULL DEFAULT uuid_generate_v4() UNIQUE,
  started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at      TIMESTAMPTZ NOT NULL,
  ended_at        TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (admin_user_id <> target_user_id),
  CHECK (expires_at > started_at)
);

CREATE INDEX idx_impersonation_admin ON public.impersonation_sessions(admin_user_id, started_at DESC);
CREATE INDEX idx_impersonation_target ON public.impersonation_sessions(target_user_id, started_at DESC);
CREATE INDEX idx_impersonation_workspace ON public.impersonation_sessions(workspace_id, started_at DESC);

CREATE OR REPLACE FUNCTION public.is_workspace_admin(p_workspace_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.my_workspace_role(p_workspace_id) IN ('ADMIN', 'MASTER');
$$;

CREATE OR REPLACE FUNCTION public.start_impersonation(
  p_target_user_id UUID,
  p_reason         TEXT,
  p_workspace_id   UUID DEFAULT NULL,
  p_ttl_minutes    INT  DEFAULT 30
)
RETURNS public.impersonation_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_session public.impersonation_sessions;
  v_is_master BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot impersonate yourself';
  END IF;

  IF p_ttl_minutes < 5 OR p_ttl_minutes > 180 THEN
    RAISE EXCEPTION 'TTL must be between 5 and 180 minutes';
  END IF;

  SELECT (global_role = 'MASTER') INTO v_is_master
  FROM public.profiles WHERE id = auth.uid();

  IF COALESCE(v_is_master, FALSE) = FALSE THEN
    IF p_workspace_id IS NULL THEN
      RAISE EXCEPTION 'workspace_id is required for non-MASTER admins';
    END IF;

    IF NOT public.is_workspace_admin(p_workspace_id) THEN
      RAISE EXCEPTION 'Only workspace ADMIN or MASTER can impersonate';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.workspace_members wm
      WHERE wm.workspace_id = p_workspace_id
        AND wm.user_id = p_target_user_id
    ) THEN
      RAISE EXCEPTION 'Target user is not member of this workspace';
    END IF;
  END IF;

  INSERT INTO public.impersonation_sessions (
    admin_user_id, target_user_id, workspace_id, reason, expires_at
  ) VALUES (
    auth.uid(), p_target_user_id, p_workspace_id, p_reason,
    NOW() + make_interval(mins => p_ttl_minutes)
  )
  RETURNING * INTO v_session;

  PERFORM public.log_activity(
    COALESCE(p_workspace_id,
      (SELECT wm.workspace_id FROM public.workspace_members wm WHERE wm.user_id = auth.uid() LIMIT 1)
    ),
    NULL,
    auth.uid(),
    'auth.impersonation_started',
    'user',
    p_target_user_id,
    jsonb_build_object('session_id', v_session.id, 'expires_at', v_session.expires_at, 'reason', p_reason)
  );

  RETURN v_session;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_impersonation(p_session_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_workspace UUID;
  v_target    UUID;
BEGIN
  UPDATE public.impersonation_sessions
  SET ended_at = NOW()
  WHERE id = p_session_id
    AND ended_at IS NULL
    AND (
      admin_user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
    )
  RETURNING workspace_id, target_user_id INTO v_workspace, v_target;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session not found or not allowed';
  END IF;

  PERFORM public.log_activity(
    COALESCE(v_workspace,
      (SELECT wm.workspace_id FROM public.workspace_members wm WHERE wm.user_id = auth.uid() LIMIT 1)
    ),
    NULL,
    auth.uid(),
    'auth.impersonation_ended',
    'user',
    v_target,
    jsonb_build_object('session_id', p_session_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_impersonation(UUID, TEXT, UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_impersonation(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS for new tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.admin_user_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "aua_select" ON public.admin_user_actions
  FOR SELECT USING (
    requested_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );

CREATE POLICY "aua_insert" ON public.admin_user_actions
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
    AND requested_by = auth.uid()
  );

CREATE POLICY "aua_update_master" ON public.admin_user_actions
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );

ALTER TABLE public.impersonation_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "impersonation_select" ON public.impersonation_sessions
  FOR SELECT USING (
    admin_user_id = auth.uid()
    OR target_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );

CREATE POLICY "impersonation_insert" ON public.impersonation_sessions
  FOR INSERT WITH CHECK (
    admin_user_id = auth.uid()
    AND (
      EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
      OR (workspace_id IS NOT NULL AND public.my_workspace_role(workspace_id) = 'ADMIN')
    )
  );

CREATE POLICY "impersonation_update" ON public.impersonation_sessions
  FOR UPDATE USING (
    admin_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );
