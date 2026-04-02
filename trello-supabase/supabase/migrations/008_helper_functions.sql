-- =============================================================================
-- MIGRATION 008: Funções auxiliares para o frontend
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Buscar user_id pelo e-mail (usado na tela de membros)
-- SECURITY DEFINER para acessar auth.users com segurança
-- Retorna NULL se não encontrado
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_id_by_email(p_email TEXT)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT id FROM auth.users WHERE email = lower(trim(p_email)) LIMIT 1;
$$;

-- Garante que apenas usuários autenticados podem chamar
REVOKE ALL ON FUNCTION public.get_user_id_by_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_id_by_email(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- Estatísticas rápidas de um workspace (usado no dashboard)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.workspace_stats(p_workspace_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'total',     COUNT(*),
    'completed', COUNT(*) FILTER (WHERE card_status = 'completed'),
    'overdue',   COUNT(*) FILTER (WHERE is_overdue = TRUE),
    'active',    COUNT(*) FILTER (WHERE card_status = 'active' AND is_overdue = FALSE)
  )
  FROM public.v_cards_full
  WHERE workspace_id = p_workspace_id;
$$;

GRANT EXECUTE ON FUNCTION public.workspace_stats(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Mover cartão com reordenação automática de posição
-- Evita que o frontend precise calcular posições
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.move_card(
  p_card_id      UUID,
  p_target_list  UUID,
  p_after_card   UUID DEFAULT NULL  -- NULL = colocar no início
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pos FLOAT;
  v_prev FLOAT;
  v_next FLOAT;
BEGIN
  IF p_after_card IS NULL THEN
    -- Colocar antes do primeiro cartão
    SELECT COALESCE(MIN(position) - 1, 1)
    INTO   v_pos
    FROM   public.cards WHERE list_id = p_target_list AND is_archived = FALSE;
  ELSE
    -- Pegar posição do cartão anterior e do próximo
    SELECT position INTO v_prev FROM public.cards WHERE id = p_after_card;
    SELECT MIN(position) INTO v_next
    FROM   public.cards
    WHERE  list_id = p_target_list AND position > v_prev AND id <> p_card_id AND is_archived = FALSE;

    IF v_next IS NULL THEN
      v_pos := v_prev + 1;
    ELSE
      v_pos := (v_prev + v_next) / 2.0;
    END IF;

    -- Se a diferença ficar muito pequena, rebalancear a lista
    IF ABS(v_pos - v_prev) < 0.001 THEN
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY position) * 1000 AS new_pos
        FROM   public.cards WHERE list_id = p_target_list AND is_archived = FALSE
      )
      UPDATE public.cards c SET position = r.new_pos FROM ranked r WHERE r.id = c.id;
      -- Recalcular após rebalanceamento
      SELECT position INTO v_prev FROM public.cards WHERE id = p_after_card;
      v_pos := v_prev + 500;
    END IF;
  END IF;

  UPDATE public.cards
  SET    list_id = p_target_list, position = v_pos
  WHERE  id = p_card_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.move_card(UUID, UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Notificações não lidas de um usuário
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_unread_notifications()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COUNT(*) FROM public.notifications
  WHERE user_id = auth.uid() AND is_read = FALSE;
$$;

GRANT EXECUTE ON FUNCTION public.my_unread_notifications() TO authenticated;
