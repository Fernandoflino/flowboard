-- =============================================================================
-- RELATÓRIOS EXECUTIVOS — SQL COMPLETO
-- RF42 – RF45
-- =============================================================================
-- Todos os queries usam a view v_cards_full, que herda RLS das tabelas base.
-- Substitua os parâmetros marcados com :param pelo valor desejado.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- RELATÓRIO 1: Visão Geral de Cartões (RF42)
-- Todos os campos exigidos pelo requisito.
-- ---------------------------------------------------------------------------
SELECT
  card_id,
  card_title,
  card_description,
  workspace_name,
  board_name,
  list_name,
  card_status,
  card_created_at,
  completed_at,
  due_date,
  is_overdue,
  hours_to_complete,
  assignees,
  labels,
  custom_fields,
  checklist_progress,
  attachment_count,
  comment_count
FROM  public.v_cards_full
WHERE is_archived = FALSE
ORDER BY card_created_at DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 2: Filtros combinados (RF43)
-- Parâmetros opcionais; comente/remova os que não precisar.
-- ---------------------------------------------------------------------------
SELECT *
FROM  public.v_cards_full
WHERE is_archived = FALSE

  -- por período
  AND card_created_at BETWEEN :data_inicio AND :data_fim

  -- por workspace
  AND workspace_id = :workspace_id

  -- por board
  AND board_id = :board_id

  -- por status
  AND card_status = :status     -- 'active' | 'completed' | 'overdue' | 'archived'

  -- por usuário responsável (cartões onde o usuário é assignee)
  AND EXISTS (
    SELECT 1 FROM public.card_members cm
    WHERE cm.card_id = v_cards_full.card_id
      AND cm.user_id = :user_id
  )

ORDER BY card_created_at DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 3: Tarefas por Usuário (RF44)
-- Quantos cartões cada usuário tem (como responsável).
-- ---------------------------------------------------------------------------
SELECT
  p.id                              AS user_id,
  p.full_name                       AS user_name,
  COUNT(cm.card_id)                 AS total_cards,
  COUNT(cm.card_id) FILTER (
    WHERE c.status = 'completed'
  )                                 AS completed_cards,
  COUNT(cm.card_id) FILTER (
    WHERE c.status = 'active' AND c.due_date < NOW()
  )                                 AS overdue_cards,
  COUNT(cm.card_id) FILTER (
    WHERE c.status = 'active' AND c.due_date >= NOW()
  )                                 AS on_track_cards,
  ROUND(
    AVG(EXTRACT(EPOCH FROM (c.completed_at - c.created_at))/3600.0)
      FILTER (WHERE c.status = 'completed'),
    2
  )                                 AS avg_hours_to_complete
FROM        public.profiles     p
JOIN        public.card_members cm ON cm.user_id = p.id
JOIN        public.cards        c  ON c.id = cm.card_id
JOIN        public.lists        l  ON l.id = c.list_id
JOIN        public.boards       b  ON b.id = l.board_id
WHERE       b.workspace_id = :workspace_id   -- filtre por workspace
  AND       c.is_archived  = FALSE
GROUP BY    p.id, p.full_name
ORDER BY    total_cards DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 4: Métricas de Conclusão e Atraso (RF44)
-- Painel executivo com totais e tempo médio.
-- ---------------------------------------------------------------------------
SELECT
  w.name                                                AS workspace,
  b.name                                                AS board,
  COUNT(c.id)                                           AS total_cards,
  COUNT(c.id) FILTER (WHERE c.status = 'completed')    AS total_completed,
  COUNT(c.id) FILTER (
    WHERE c.status = 'active' AND c.due_date < NOW()
  )                                                     AS total_overdue,
  ROUND(
    100.0 * COUNT(c.id) FILTER (WHERE c.status = 'completed')
    / NULLIF(COUNT(c.id), 0),
    1
  )                                                     AS completion_pct,
  ROUND(
    AVG(EXTRACT(EPOCH FROM (c.completed_at - c.created_at))/3600.0)
      FILTER (WHERE c.status = 'completed'),
    1
  )                                                     AS avg_hours_to_complete,
  ROUND(
    AVG(EXTRACT(EPOCH FROM (c.completed_at - c.due_date))/3600.0)
      FILTER (WHERE c.status = 'completed' AND c.completed_at > c.due_date),
    1
  )                                                     AS avg_hours_late_when_late
FROM      public.cards        c
JOIN      public.lists        l  ON l.id = c.list_id
JOIN      public.boards       b  ON b.id = l.board_id
JOIN      public.workspaces   w  ON w.id = b.workspace_id
WHERE     c.is_archived = FALSE
  AND     b.workspace_id = :workspace_id          -- opcional
  AND     c.created_at BETWEEN :data_inicio AND :data_fim  -- opcional
GROUP BY  w.name, b.name
ORDER BY  total_cards DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 5: Cartões Atrasados Detalhado
-- ---------------------------------------------------------------------------
SELECT
  card_title,
  board_name,
  list_name,
  workspace_name,
  due_date,
  NOW() - due_date                      AS overdue_duration,
  EXTRACT(DAY FROM NOW() - due_date)    AS days_overdue,
  assignees,
  card_status
FROM  public.v_cards_full
WHERE card_status = 'active'
  AND due_date    < NOW()
  AND is_archived = FALSE
  AND workspace_id = :workspace_id
ORDER BY days_overdue DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 6: Histórico de Atividades (Audit trail) para um cartão
-- ---------------------------------------------------------------------------
SELECT
  al.created_at,
  al.action_type,
  p.full_name      AS actor,
  al.metadata
FROM  public.activity_logs al
JOIN  public.profiles p ON p.id = al.user_id
WHERE al.entity_id   = :card_id
  AND al.entity_type = 'card'
ORDER BY al.created_at DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 7: Volume de atividade por período (dashboard executivo)
-- ---------------------------------------------------------------------------
SELECT
  DATE_TRUNC('day', al.created_at) AS day,
  al.action_type,
  COUNT(*)                          AS events
FROM  public.activity_logs al
WHERE al.workspace_id = :workspace_id
  AND al.created_at   BETWEEN :data_inicio AND :data_fim
GROUP BY 1, 2
ORDER BY 1, 3 DESC;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 8: Burndown — cartões criados vs concluídos por dia
-- ---------------------------------------------------------------------------
WITH daily AS (
  SELECT
    DATE_TRUNC('day', created_at)::DATE AS day,
    COUNT(*)                             AS created,
    COUNT(*) FILTER (WHERE status = 'completed'
                     AND DATE_TRUNC('day', completed_at)::DATE = DATE_TRUNC('day', created_at)::DATE)
                                         AS completed_same_day
  FROM  public.cards
  WHERE list_id IN (
    SELECT l.id FROM public.lists l
    JOIN public.boards b ON b.id = l.board_id
    WHERE b.workspace_id = :workspace_id
  )
    AND created_at BETWEEN :data_inicio AND :data_fim
    AND is_archived = FALSE
  GROUP BY 1
),
completed_by_day AS (
  SELECT
    DATE_TRUNC('day', completed_at)::DATE AS day,
    COUNT(*) AS completed
  FROM  public.cards
  WHERE status = 'completed'
    AND list_id IN (
      SELECT l.id FROM public.lists l
      JOIN public.boards b ON b.id = l.board_id
      WHERE b.workspace_id = :workspace_id
    )
    AND completed_at BETWEEN :data_inicio AND :data_fim
  GROUP BY 1
)
SELECT
  d.day,
  d.created,
  COALESCE(cd.completed, 0)          AS completed,
  SUM(d.created - COALESCE(cd.completed, 0))
    OVER (ORDER BY d.day)             AS open_running_total
FROM       daily          d
LEFT JOIN  completed_by_day cd ON cd.day = d.day
ORDER BY   d.day;


-- ---------------------------------------------------------------------------
-- RELATÓRIO 9: Cartões por etiqueta
-- ---------------------------------------------------------------------------
SELECT
  lb.name                   AS label_name,
  lb.color                  AS label_color,
  COUNT(cl.card_id)         AS total_cards,
  COUNT(cl.card_id) FILTER (
    WHERE c.status = 'completed'
  )                         AS completed,
  COUNT(cl.card_id) FILTER (
    WHERE c.status = 'active' AND c.due_date < NOW()
  )                         AS overdue
FROM      public.labels      lb
JOIN      public.card_labels cl ON cl.label_id = lb.id
JOIN      public.cards       c  ON c.id = cl.card_id
JOIN      public.lists       l  ON l.id = c.list_id
JOIN      public.boards      b  ON b.id = l.board_id
WHERE     b.workspace_id = :workspace_id
  AND     c.is_archived = FALSE
GROUP BY  lb.id, lb.name, lb.color
ORDER BY  total_cards DESC;
