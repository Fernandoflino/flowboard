-- =============================================================================
-- MIGRATION 006: Row-Level Security (RLS) — ALL TABLES
-- =============================================================================
-- Strategy:
--   1. Enable RLS on every table.
--   2. MASTER bypasses all restrictions via helper function.
--   3. Workspace membership gates all data access.
--   4. Write operations restricted by role (ADMIN > MEMBER > VIEWER).
--   5. Logs are INSERT-only (no UPDATE/DELETE except MASTER).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PROFILES
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read profiles (needed for mentions, member lists)
CREATE POLICY "profiles_select" ON public.profiles
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- User can update their own profile; MASTER can update anyone
CREATE POLICY "profiles_update_self" ON public.profiles
  FOR UPDATE USING (
    id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );

-- Only MASTER can delete profiles (RF08 trigger prevents deleting last MASTER)
CREATE POLICY "profiles_delete_master" ON public.profiles
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.global_role = 'MASTER')
  );

-- ---------------------------------------------------------------------------
-- WORKSPACES
-- ---------------------------------------------------------------------------
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workspaces_select" ON public.workspaces
  FOR SELECT USING (public.is_workspace_member(id));

CREATE POLICY "workspaces_insert" ON public.workspaces
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);  -- any authenticated user can create

CREATE POLICY "workspaces_update" ON public.workspaces
  FOR UPDATE USING (
    public.my_workspace_role(id) IN ('ADMIN','MASTER')
  );

CREATE POLICY "workspaces_delete" ON public.workspaces
  FOR DELETE USING (
    public.my_workspace_role(id) = 'MASTER'
    OR owner_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- WORKSPACE MEMBERS
-- ---------------------------------------------------------------------------
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wm_select" ON public.workspace_members
  FOR SELECT USING (public.is_workspace_member(workspace_id));

-- Only ADMIN/MASTER can add/change members
CREATE POLICY "wm_insert" ON public.workspace_members
  FOR INSERT WITH CHECK (
    public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
  );

CREATE POLICY "wm_update" ON public.workspace_members
  FOR UPDATE USING (
    public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
  );

CREATE POLICY "wm_delete" ON public.workspace_members
  FOR DELETE USING (
    user_id = auth.uid()  -- member can leave
    OR public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- BOARDS
-- ---------------------------------------------------------------------------
ALTER TABLE public.boards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "boards_select" ON public.boards
  FOR SELECT USING (
    public.is_workspace_member(workspace_id)
    AND (
      visibility = 'public'
      OR visibility = 'workspace'
      OR public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
    )
  );

CREATE POLICY "boards_insert" ON public.boards
  FOR INSERT WITH CHECK (
    public.my_workspace_role(workspace_id) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "boards_update" ON public.boards
  FOR UPDATE USING (
    public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
    OR created_by = auth.uid()
  );

CREATE POLICY "boards_delete" ON public.boards
  FOR DELETE USING (
    public.my_workspace_role(workspace_id) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- LISTS
-- Helper: get workspace_id via board
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_board_workspace(p_board_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT workspace_id FROM public.boards WHERE id = p_board_id;
$$;

ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lists_select" ON public.lists
  FOR SELECT USING (
    public.is_workspace_member(public.get_board_workspace(board_id))
  );

CREATE POLICY "lists_insert" ON public.lists
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "lists_update" ON public.lists
  FOR UPDATE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "lists_delete" ON public.lists
  FOR DELETE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- CARDS
-- Helper: get workspace_id via list→board
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_list_workspace(p_list_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT b.workspace_id
  FROM public.lists l JOIN public.boards b ON b.id = l.board_id
  WHERE l.id = p_list_id;
$$;

ALTER TABLE public.cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cards_select" ON public.cards
  FOR SELECT USING (
    public.is_workspace_member(public.get_list_workspace(list_id))
  );

CREATE POLICY "cards_insert" ON public.cards
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_list_workspace(list_id)) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "cards_update" ON public.cards
  FOR UPDATE USING (
    public.my_workspace_role(public.get_list_workspace(list_id)) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "cards_delete" ON public.cards
  FOR DELETE USING (
    public.my_workspace_role(public.get_list_workspace(list_id)) IN ('ADMIN','MASTER')
    OR created_by = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- CARD MEMBERS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_card_workspace_from_cm(p_card_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.get_list_workspace(list_id) FROM public.cards WHERE id = p_card_id;
$$;

ALTER TABLE public.card_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "card_members_select" ON public.card_members
  FOR SELECT USING (
    public.is_workspace_member(public.get_card_workspace_from_cm(card_id))
  );

CREATE POLICY "card_members_insert" ON public.card_members
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_card_workspace_from_cm(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "card_members_delete" ON public.card_members
  FOR DELETE USING (
    public.my_workspace_role(public.get_card_workspace_from_cm(card_id)) IN ('ADMIN','MEMBER','MASTER')
    OR user_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- CARD COMMENTS
-- ---------------------------------------------------------------------------
ALTER TABLE public.card_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "card_comments_select" ON public.card_comments
  FOR SELECT USING (
    public.is_workspace_member(public.get_card_workspace(card_id))
  );

CREATE POLICY "card_comments_insert" ON public.card_comments
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );

-- Users can only edit their own comments; ADMINs/MASTER can edit any
CREATE POLICY "card_comments_update" ON public.card_comments
  FOR UPDATE USING (
    user_id = auth.uid()
    OR public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MASTER')
  );

CREATE POLICY "card_comments_delete" ON public.card_comments
  FOR DELETE USING (
    user_id = auth.uid()
    OR public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- CHECKLISTS & ITEMS
-- ---------------------------------------------------------------------------
ALTER TABLE public.checklists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "checklists_select" ON public.checklists
  FOR SELECT USING (public.is_workspace_member(public.get_card_workspace(card_id)));
CREATE POLICY "checklists_insert" ON public.checklists
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "checklists_update" ON public.checklists
  FOR UPDATE USING (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "checklists_delete" ON public.checklists
  FOR DELETE USING (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MASTER')
  );

ALTER TABLE public.checklist_items ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_checklist_workspace(p_cl_id UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.get_card_workspace(card_id) FROM public.checklists WHERE id = p_cl_id;
$$;

CREATE POLICY "checklist_items_select" ON public.checklist_items
  FOR SELECT USING (public.is_workspace_member(public.get_checklist_workspace(checklist_id)));
CREATE POLICY "checklist_items_insert" ON public.checklist_items
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_checklist_workspace(checklist_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "checklist_items_update" ON public.checklist_items
  FOR UPDATE USING (
    public.my_workspace_role(public.get_checklist_workspace(checklist_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "checklist_items_delete" ON public.checklist_items
  FOR DELETE USING (
    public.my_workspace_role(public.get_checklist_workspace(checklist_id)) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- LABELS & CARD_LABELS
-- ---------------------------------------------------------------------------
ALTER TABLE public.labels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "labels_select" ON public.labels
  FOR SELECT USING (public.is_workspace_member(public.get_board_workspace(board_id)));
CREATE POLICY "labels_insert" ON public.labels
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "labels_update" ON public.labels
  FOR UPDATE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );
CREATE POLICY "labels_delete" ON public.labels
  FOR DELETE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );

ALTER TABLE public.card_labels ENABLE ROW LEVEL SECURITY;

CREATE POLICY "card_labels_select" ON public.card_labels
  FOR SELECT USING (public.is_workspace_member(public.get_card_workspace(card_id)));
CREATE POLICY "card_labels_insert" ON public.card_labels
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "card_labels_delete" ON public.card_labels
  FOR DELETE USING (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );

-- ---------------------------------------------------------------------------
-- ATTACHMENTS
-- ---------------------------------------------------------------------------
ALTER TABLE public.card_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attachments_select" ON public.card_attachments
  FOR SELECT USING (public.is_workspace_member(public.get_card_workspace(card_id)));
CREATE POLICY "attachments_insert" ON public.card_attachments
  FOR INSERT WITH CHECK (
    uploaded_by = auth.uid()
    AND public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "attachments_delete" ON public.card_attachments
  FOR DELETE USING (
    uploaded_by = auth.uid()
    OR public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- CUSTOM FIELDS & VALUES
-- ---------------------------------------------------------------------------
ALTER TABLE public.custom_fields ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cf_select" ON public.custom_fields
  FOR SELECT USING (public.is_workspace_member(public.get_board_workspace(board_id)));
CREATE POLICY "cf_insert" ON public.custom_fields
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );
CREATE POLICY "cf_update" ON public.custom_fields
  FOR UPDATE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );
CREATE POLICY "cf_delete" ON public.custom_fields
  FOR DELETE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );

ALTER TABLE public.custom_field_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cfv_select" ON public.custom_field_values
  FOR SELECT USING (public.is_workspace_member(public.get_card_workspace(card_id)));
CREATE POLICY "cfv_insert" ON public.custom_field_values
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "cfv_update" ON public.custom_field_values
  FOR UPDATE USING (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MEMBER','MASTER')
  );
CREATE POLICY "cfv_delete" ON public.custom_field_values
  FOR DELETE USING (
    public.my_workspace_role(public.get_card_workspace(card_id)) IN ('ADMIN','MASTER')
  );

-- ---------------------------------------------------------------------------
-- ACTIVITY LOGS — INSERT-ONLY for non-MASTER
-- ---------------------------------------------------------------------------
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "logs_select" ON public.activity_logs
  FOR SELECT USING (public.is_workspace_member(workspace_id));

CREATE POLICY "logs_insert" ON public.activity_logs
  FOR INSERT WITH CHECK (public.is_workspace_member(workspace_id));

-- MASTER only update/delete (for GDPR erasure, etc.)
CREATE POLICY "logs_update_master" ON public.activity_logs
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND global_role = 'MASTER')
  );
CREATE POLICY "logs_delete_master" ON public.activity_logs
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND global_role = 'MASTER')
  );

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notif_select" ON public.notifications
  FOR SELECT USING (user_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND global_role = 'MASTER')
  );
CREATE POLICY "notif_update" ON public.notifications
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "notif_delete" ON public.notifications
  FOR DELETE USING (user_id = auth.uid() OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND global_role = 'MASTER')
  );

-- ---------------------------------------------------------------------------
-- AUTOMATIONS
-- ---------------------------------------------------------------------------
ALTER TABLE public.automations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auto_select" ON public.automations
  FOR SELECT USING (public.is_workspace_member(public.get_board_workspace(board_id)));
CREATE POLICY "auto_insert" ON public.automations
  FOR INSERT WITH CHECK (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );
CREATE POLICY "auto_update" ON public.automations
  FOR UPDATE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );
CREATE POLICY "auto_delete" ON public.automations
  FOR DELETE USING (
    public.my_workspace_role(public.get_board_workspace(board_id)) IN ('ADMIN','MASTER')
  );

ALTER TABLE public.automation_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auto_runs_select" ON public.automation_runs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.automations a
      WHERE a.id = automation_id
        AND public.is_workspace_member(public.get_board_workspace(a.board_id))
    )
  );
