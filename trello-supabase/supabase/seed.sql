-- =============================================================================
-- SEED: Dados iniciais (RF62)
-- ATENÇÃO: Execute DEPOIS das migrations e DEPOIS do primeiro login do usuário
-- MASTER via Supabase Auth (dashboard ou CLI).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PASSO 1: Promover o primeiro usuário a MASTER
-- Substitua 'master@suaempresa.com' pelo e-mail real.
-- ---------------------------------------------------------------------------
UPDATE public.profiles
SET    global_role = 'MASTER'
WHERE  id = (
  SELECT id FROM auth.users WHERE email = 'fernandoflino95@gmail.com' LIMIT 1
);

-- ---------------------------------------------------------------------------
-- PASSO 2: Workspace de demonstração
-- ---------------------------------------------------------------------------
INSERT INTO public.workspaces (id, name, description, owner_id)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Workspace Demo',
  'Workspace de demonstração criado pelo seed.',
  (SELECT id FROM auth.users WHERE email = 'fernandoflino95@gmail.com' LIMIT 1)
);
-- O trigger handle_workspace_created adiciona automaticamente o owner como ADMIN.

-- ---------------------------------------------------------------------------
-- PASSO 3: Board de demonstração
-- ---------------------------------------------------------------------------
INSERT INTO public.boards (id, workspace_id, name, visibility, created_by)
VALUES (
  'bbbbbbbb-0000-0000-0000-000000000001',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'Board Principal',
  'workspace',
  (SELECT id FROM auth.users WHERE email = 'fernandoflino95@gmail.com' LIMIT 1)
);

-- ---------------------------------------------------------------------------
-- PASSO 4: Listas padrão (estilo Kanban)
-- ---------------------------------------------------------------------------
INSERT INTO public.lists (id, board_id, name, position) VALUES
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Backlog',      1),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', 'Em Progresso', 2),
  ('cccccccc-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000001', 'Em Revisão',   3),
  ('cccccccc-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000001', 'Concluído',    4);

-- ---------------------------------------------------------------------------
-- PASSO 5: Etiquetas padrão
-- ---------------------------------------------------------------------------
INSERT INTO public.labels (board_id, name, color) VALUES
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Bug',          '#EF4444'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Melhoria',     '#3B82F6'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Urgente',      '#F59E0B'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Feature',      '#10B981'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Documentação', '#8B5CF6');

-- ---------------------------------------------------------------------------
-- PASSO 6: Campos personalizados de exemplo
-- ---------------------------------------------------------------------------
INSERT INTO public.custom_fields (board_id, name, field_type, position) VALUES
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Sprint',       'list',    1),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Story Points', 'number',  2),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Bloqueado',    'boolean', 3);

UPDATE public.custom_fields
SET    options = '["Sprint 1","Sprint 2","Sprint 3","Sprint 4"]'
WHERE  name = 'Sprint'
  AND  board_id = 'bbbbbbbb-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------
-- PASSO 7: Cartão de exemplo
-- ---------------------------------------------------------------------------
INSERT INTO public.cards (id, list_id, title, description, status, position, created_by)
VALUES (
  'dddddddd-0000-0000-0000-000000000001',
  'cccccccc-0000-0000-0000-000000000001',
  'Configurar ambiente de desenvolvimento',
  'Instalar Docker, Supabase CLI e configurar variáveis de ambiente.',
  'active',
  1,
  (SELECT id FROM auth.users WHERE email = 'fernandoflino95@gmail.com' LIMIT 1)
);
