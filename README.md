# FlowBoard — Validação de Requisitos e Guia do Projeto

Este repositório implementa um sistema SaaS estilo Trello (multi-tenant por workspace) com frontend em HTML/CSS/JS e backend em Supabase/PostgreSQL.

## 1) Resumo executivo

- **Status geral:** o projeto atende **a maior parte** dos requisitos funcionais e técnicos, principalmente modelagem, RLS, auditoria, relatórios e migração.
- **Lacunas principais encontradas:**
  1. **RF06 (MASTER criar/editar/excluir/reset de usuários)** está **parcial**: a fila segura foi implementada, mas requer worker server-side para efetivar ações no Auth.
  2. **RF51** permanece com cobertura parcial em operações CRUD não aplicáveis em algumas entidades.

---

## Resposta direta sobre a pergunta “todos os requisitos estão na plataforma?”

**Não.** A implementação atual cobre a maior parte dos requisitos, mas **não 100%**.

Pendências objetivas:
- **RF06**: gestão completa de usuários pelo MASTER (criar/editar/excluir/reset) (**parcial**).
- **RF51**: cobertura formal de policies CRUD completas em 100% das entidades (**parcial em pontos específicos**).

## 2) Arquitetura e stack

- **Frontend:** páginas estáticas e scripts JS com cliente Supabase.
- **Backend:** PostgreSQL + Auth + Storage + RLS no Supabase.
- **Banco:** migrations SQL versionadas (`001` a `009`) + `seed.sql`.
- **Relatórios:** SQL dedicado em `reports/executive_reports.sql`.

### Estrutura

```text
frontend/
  index.html
  login.html
  pages/*.html
  js/supabase.js
  css/style.css

trello-supabase/
  supabase/
    config.toml
    seed.sql
    migrations/*.sql
  docs/
    ARCHITECTURE.md
    ENV.md
  reports/
    executive_reports.sql
```

---

## 3) Matriz de conformidade (RF01–RF62)

Legenda:
- ✅ Implementado
- ⚠️ Parcial
- ❌ Não implementado

### Usuários e autenticação
- ✅ **RF01** Cadastro (nome/email/senha) via Supabase Auth + trigger de profile.
- ✅ **RF02** Login/autenticação via Supabase Auth.
- ✅ **RF03** Recuperação de senha prevista no frontend e stack Supabase.
- ✅ **RF04** Perfil com nome, foto e preferências (`profiles`).

### Administração
- ✅ **RF05** Usuário MASTER previsto (`global_role = 'MASTER'`).
- ⚠️ **RF06** MASTER gerir usuários (criar/editar/excluir/reset) **parcial**: suporte de permissões existe, mas sem fluxo completo explícito no projeto para todas as operações.
- ✅ **RF07** Roles MASTER/ADMIN/MEMBER/VIEWER.
- ✅ **RF08** MASTER não pode ser excluído/rebaixado (trigger `protect_master`).
- ✅ **RF09** Impersonação por ADMIN implementada com sessão auditável (`start_impersonation`/`end_impersonation`).

### Workspaces (multi-tenant)
- ✅ **RF10** Criar workspace.
- ✅ **RF11** Workspace com nome/descrição.
- ✅ **RF12** `workspace_members` com `user_id`, `workspace_id`, `role`.
- ✅ **RF13** Isolamento por workspace via RLS.

### Boards/Listas/Cartões
- ✅ **RF14** Board pertence a workspace.
- ✅ **RF15** Board com nome e visibilidade.
- ✅ **RF16** Lista pertence a board.
- ✅ **RF17** Lista com nome e posição persistida.
- ✅ **RF18** Cartão pertence a lista.
- ✅ **RF19** Cartão com título, descrição, posição, timestamps, status e `completed_at`.
- ✅ **RF20** Movimentação de cartão entre listas (inclusive função `move_card`).
- ✅ **RF21** Múltiplos responsáveis (`card_members`).

### Detalhes do cartão
- ✅ **RF22** Comentários (`card_comments`).
- ✅ **RF23** Checklists.
- ✅ **RF24** Itens com status feito/não feito.
- ✅ **RF25** Datas de início e entrega (`start_date`, `due_date`).
- ✅ **RF26** Etiquetas com cor + N:N (`card_labels`).

### Personalização, anexos e movimentação
- ✅ **RF27** Cor e imagem de capa no cartão.
- ✅ **RF28** Anexos em cartão.
- ✅ **RF29** Anexo com URL/tipo/nome.
- ✅ **RF30** Flag de imagem (`is_image`) e suporte de visualização no frontend.
- ✅ **RF31** Mover/reordenar cartões e listas.
- ✅ **RF32** Posição persistida no banco (FLOAT + função de rebalanceamento).

### Notificações, busca, campos customizados e automação
- ✅ **RF33** Estrutura de notificações com eventos.
- ✅ **RF34** Busca por título/descrição (índice FTS).
- ✅ **RF35** Filtros por membro/etiqueta/data/status (consultas e telas).
- ✅ **RF36** Campos customizados.
- ✅ **RF37** Tipos texto/número/data/lista/booleano.
- ✅ **RF38** Estrutura base de automação (`automations`, `automation_runs`).

### Visualizações
- ✅ **RF39** Implementado com telas dedicadas `calendar.html` e `timeline.html`.

### Auditoria e relatórios
- ✅ **RF40** `activity_logs` com campos críticos.
- ✅ **RF41** Triggers para logs automáticos (criação/movimentação/edição/comentário/exclusão).
- ✅ **RF42** Relatórios com visão completa por cartão (`v_cards_full`).
- ✅ **RF43** Filtros por período/usuário/workspace/board/status.
- ✅ **RF44** Métricas obrigatórias (tarefas por usuário, concluídas, atrasadas, tempo médio).
- ✅ **RF45** SQL pronto em `reports/executive_reports.sql`.

### Arquitetura Supabase, RLS e segurança
- ✅ **RF46** Suporte a Supabase local (Docker).
- ✅ **RF47** Estrutura `/supabase/migrations` e `/supabase/seed.sql`.
- ✅ **RF48** Tudo via migrations SQL (tabelas, índices, constraints, triggers, funções, RLS).
- ✅ **RF49** RLS aplicado às tabelas de domínio.
- ✅ **RF50** Regras de acesso por membership + MASTER + ADMIN.
- ⚠️ **RF51** Parcial: políticas completas existem na maioria das tabelas; em algumas entidades há apenas operações necessárias (por exemplo, sem `UPDATE` quando não aplicável).
- ✅ **RF52** Uso consistente de `auth.uid()` em policies e funções.
- ✅ **RF53** Validação no banco com RLS/constraints/triggers.
- ✅ **RF54** Menor privilégio por role e escopo.
- ✅ **RF55** Uso extensivo de UUID.
- ✅ **RF56** Validações por constraints/checks.

### Storage, migração, env e seed
- ✅ **RF57** Storage preparado para anexos e avatares.
- ✅ **RF58** Restrição de acesso por membro de workspace no bucket de anexos.
- ✅ **RF59** Estratégia de migração sem retrabalho documentada.
- ✅ **RF60** Inclui `supabase db push` e `supabase db dump` na documentação.
- ✅ **RF61** Variáveis de ambiente documentadas.
- ✅ **RF62** `seed.sql` com dados iniciais.

---

## 4) Como rodar (local)

### Backend (Supabase)

```bash
cd trello-supabase
supabase start
supabase db reset
```

### Frontend

```bash
cd frontend
serve .
```

Acesse `http://localhost:3000`.

---

## 5) Segurança aplicada

- RLS em tabelas de domínio com helper functions (`is_workspace_member`, `my_workspace_role`).
- Triggers para auditoria imutável (`activity_logs`, update/delete só MASTER).
- Validação no banco (constraints/checks/foreign keys).
- Isolamento tenant por `workspace_id` em toda a cadeia (workspace → board → list → card e derivados).
- Policies para `storage.objects` em anexos e avatares.

---

## 6) Lacunas e próximos passos recomendados

1. **Fechar RF06 ponta-a-ponta** conectando a fila `admin_user_actions` a um worker/Edge Function com `SERVICE_ROLE_KEY`.
2. **Evoluir RF09** com UI dedicada para iniciar/encerrar impersonação e banner de sessão ativa.
3. **Validar UX avançada de RF39** (filtros, zoom e agrupamentos) nas telas de calendário e timeline.
4. **Aprimorar RF51** para explicitar intencionalmente políticas ausentes por tabela (quando não houver operação aplicável) e garantir cobertura formal por checklist automático.

---

## 7) Referências internas

- Arquitetura: `trello-supabase/docs/ARCHITECTURE.md`
- Ambiente e migração: `trello-supabase/docs/ENV.md`
- Migrations: `trello-supabase/supabase/migrations/*.sql`
- Relatórios SQL: `trello-supabase/reports/executive_reports.sql`
- Frontend guia: `frontend/README.md`


## 8) Ação necessária no Supabase

Após atualizar o código, você precisa aplicar as migrations para criar as novas estruturas de impersonação/admin:

```bash
cd trello-supabase
supabase db push
# ou, em ambiente local de desenvolvimento
supabase db reset
```

Isso cria principalmente a migration `009_admin_impersonation_and_views.sql`.
