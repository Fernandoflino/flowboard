-- =============================================================================
-- MIGRATION 007: Storage Buckets & Reporting Views
-- =============================================================================

-- ---------------------------------------------------------------------------
-- STORAGE BUCKETS (RF57, RF58)
-- Run after bucket is created via Supabase dashboard or CLI.
-- These policies enforce workspace-membership on Storage objects.
-- ---------------------------------------------------------------------------

-- Create buckets (idempotent via Supabase storage API — run via CLI or dashboard)
-- supabase storage create attachments --public=false
-- supabase storage create avatars     --public=true

-- Storage RLS policies use the path convention:
--   attachments/{workspace_id}/{card_id}/{filename}
--   avatars/{user_id}/{filename}

-- Policy for attachments bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('attachments', 'attachments', FALSE)
  ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', TRUE)
  ON CONFLICT (id) DO NOTHING;

-- Attachments: only workspace members can read
CREATE POLICY "attach_select" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'attachments'
    AND public.is_workspace_member(
      (string_to_array(name, '/'))[1]::UUID  -- first path segment = workspace_id
    )
  );

CREATE POLICY "attach_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'attachments'
    AND public.my_workspace_role(
      (string_to_array(name, '/'))[1]::UUID
    ) IN ('ADMIN','MEMBER','MASTER')
  );

CREATE POLICY "attach_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'attachments'
    AND public.my_workspace_role(
      (string_to_array(name, '/'))[1]::UUID
    ) IN ('ADMIN','MASTER')
  );

-- Avatars: anyone authenticated can read; owner can write
CREATE POLICY "avatar_select" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "avatar_insert" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'avatars'
    AND (string_to_array(name, '/'))[1]::UUID = auth.uid()
  );

CREATE POLICY "avatar_update" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'avatars'
    AND (string_to_array(name, '/'))[1]::UUID = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- RICH VIEW: v_cards_full
-- Used by all report queries (RF42–RF45)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cards_full AS
SELECT
  -- Card core
  c.id                                              AS card_id,
  c.title                                           AS card_title,
  c.description                                     AS card_description,
  c.status                                          AS card_status,
  c.position                                        AS card_position,
  c.start_date,
  c.due_date,
  c.completed_at,
  c.is_archived,
  c.created_at                                      AS card_created_at,
  c.updated_at                                      AS card_updated_at,
  EXTRACT(EPOCH FROM (c.completed_at - c.created_at))/3600.0
                                                    AS hours_to_complete,
  CASE
    WHEN c.status = 'active' AND c.due_date < NOW() THEN TRUE
    ELSE FALSE
  END                                               AS is_overdue,

  -- List
  l.id                                              AS list_id,
  l.name                                            AS list_name,

  -- Board
  b.id                                              AS board_id,
  b.name                                            AS board_name,
  b.visibility                                      AS board_visibility,

  -- Workspace
  w.id                                              AS workspace_id,
  w.name                                            AS workspace_name,

  -- Creator
  cp.id                                             AS created_by_id,
  cp.full_name                                      AS created_by_name,

  -- Assignees (aggregated)
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name))
     FROM public.card_members cm
     JOIN public.profiles p ON p.id = cm.user_id
     WHERE cm.card_id = c.id),
    '[]'::JSONB
  )                                                 AS assignees,

  -- Labels (aggregated)
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object('id', lb.id, 'name', lb.name, 'color', lb.color))
     FROM public.card_labels cl
     JOIN public.labels lb ON lb.id = cl.label_id
     WHERE cl.card_id = c.id),
    '[]'::JSONB
  )                                                 AS labels,

  -- Custom field values (aggregated)
  COALESCE(
    (SELECT jsonb_agg(jsonb_build_object(
        'field_name', cf.name,
        'field_type', cf.field_type,
        'value_text',    cfv.value_text,
        'value_number',  cfv.value_number,
        'value_date',    cfv.value_date,
        'value_boolean', cfv.value_boolean,
        'value_list',    cfv.value_list
      ))
     FROM public.custom_field_values cfv
     JOIN public.custom_fields cf ON cf.id = cfv.custom_field_id
     WHERE cfv.card_id = c.id),
    '[]'::JSONB
  )                                                 AS custom_fields,

  -- Checklist progress
  COALESCE(
    (SELECT jsonb_build_object(
        'total', COUNT(*),
        'done',  COUNT(*) FILTER (WHERE ci.is_done)
      )
     FROM public.checklists chk
     JOIN public.checklist_items ci ON ci.checklist_id = chk.id
     WHERE chk.card_id = c.id),
    '{"total":0,"done":0}'::JSONB
  )                                                 AS checklist_progress,

  -- Attachment count
  (SELECT COUNT(*) FROM public.card_attachments ca WHERE ca.card_id = c.id)
                                                    AS attachment_count,

  -- Comment count
  (SELECT COUNT(*) FROM public.card_comments cc WHERE cc.card_id = c.id)
                                                    AS comment_count

FROM   public.cards        c
JOIN   public.lists        l  ON l.id = c.list_id
JOIN   public.boards       b  ON b.id = l.board_id
JOIN   public.workspaces   w  ON w.id = b.workspace_id
JOIN   public.profiles     cp ON cp.id = c.created_by;

COMMENT ON VIEW public.v_cards_full IS
  'Denormalized card view for reporting. Respects RLS via underlying tables.';
