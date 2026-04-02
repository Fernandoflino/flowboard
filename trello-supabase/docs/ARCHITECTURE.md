# Arquitetura do Sistema — Trello Corporativo (Supabase)

## Visão Geral

Sistema multi-tenant de gerenciamento de tarefas estilo Kanban, construído sobre **Supabase (PostgreSQL + GoTrue + PostgREST + Storage)**, com foco em segurança, rastreabilidade e portabilidade.

---

## Diagrama de Entidades

```
auth.users (Supabase Auth)
    │
    │ 1:1
    ▼
profiles (global_role: MASTER|ADMIN|MEMBER|VIEWER)
    │
    │ N:N via workspace_members
    ▼
workspaces ──────────────────────────────────────────────────┐
    │                                                         │
    │ 1:N                                                     │
    ▼                                                         │
boards (visibility: private|workspace|public)                │
    │                                                         │
    │ 1:N                                                     │
    ▼                                                         │
lists (position: FLOAT)                                      │
    │                                                         │
    │ 1:N                                                     │
    ▼                                                         │
cards ──────────────────────────────────────────────────────►│
    │   └── card_members (N:N → profiles)            activity_logs
    │   └── card_comments
    │   └── checklists → checklist_items
    │   └── card_labels (N:N → labels)
    │   └── card_attachments → Storage
    │   └── custom_field_values → custom_fields
    │
    └── notifications (por user_id)
    └── automations → automation_runs
```

---

## Decisões de Design

### 1. Posição como FLOAT (listas e cartões)
Permite inserção entre dois itens sem reescrever posições de todos os outros.
Ex: posição entre 1.0 e 2.0 → 1.5. Só precisa de rebalanceamento se a diferença for < ε.

### 2. activity_logs: INSERT-ONLY para não-MASTER
RLS bloqueia UPDATE e DELETE para todos exceto MASTER. Isso garante que o log de auditoria é imutável. Nenhum usuário pode apagar seu rastro.

### 3. Helpers de RLS como SECURITY DEFINER
As funções `is_workspace_member()` e `my_workspace_role()` rodam com privilégios elevados mas são read-only. Isso evita que o planner de queries tente avaliar RLS dentro de RLS (loop infinito).

### 4. MASTER é global, não workspace-scoped
O campo `global_role = 'MASTER'` vive em `profiles`, não em `workspace_members`. O MASTER acessa tudo via bypass nas funções helper. Não pode ser rebaixado ou deletado (trigger `protect_master`).

### 5. Campos personalizados flexíveis
`custom_field_values` tem colunas separadas por tipo (`value_text`, `value_number`, etc.) em vez de um único `JSONB`. Isso permite índices, constraints de tipo e queries eficientes.

### 6. Storage com path estruturado
Caminho: `attachments/{workspace_id}/{card_id}/{filename}`
A policy RLS do Storage extrai `workspace_id` do path (position 1) e valida membership. Isso garante que a URL assinada só funciona para membros.

### 7. v_cards_full VIEW (não tabela)
Relatórios usam uma VIEW com subqueries correlacionadas para campos agregados (assignees, labels, custom fields). A view herda RLS das tabelas base automaticamente — nenhum dado vaza.

---

## Papéis e Permissões

| Ação                        | VIEWER | MEMBER | ADMIN | MASTER |
|-----------------------------|--------|--------|-------|--------|
| Ler cartões                 | ✓      | ✓      | ✓     | ✓      |
| Criar cartão                | ✗      | ✓      | ✓     | ✓      |
| Editar cartão               | ✗      | ✓      | ✓     | ✓      |
| Deletar cartão              | ✗      | próprio| ✓     | ✓      |
| Gerenciar listas            | ✗      | ✓      | ✓     | ✓      |
| Deletar lista               | ✗      | ✗      | ✓     | ✓      |
| Gerenciar members workspace | ✗      | ✗      | ✓     | ✓      |
| Criar campos customizados   | ✗      | ✗      | ✓     | ✓      |
| Criar automações            | ✗      | ✗      | ✓     | ✓      |
| Ler logs de auditoria       | ✓*     | ✓*     | ✓*    | ✓      |
| Deletar logs                | ✗      | ✗      | ✗     | ✓      |
| Gerenciar todos workspaces  | ✗      | ✗      | ✗     | ✓      |
| Rebaixar/deletar usuários   | ✗      | ✗      | ✗     | ✓      |

*Logs: membros leem apenas logs do workspace onde são membros.

---

## Segurança em Camadas

```
Browser/Client
    │
    │ SUPABASE_ANON_KEY (público, seguro)
    ▼
PostgREST API
    │
    │ JWT token (auth.uid())
    ▼
RLS Policies (banco de dados)
    │
    │ is_workspace_member() | my_workspace_role()
    ▼
Dados isolados por workspace
```

**Nunca** confiar no cliente: toda validação está no banco via constraints, triggers e RLS.

---

## Escalabilidade

- **Particionamento**: `activity_logs` pode ser particionado por `created_at` (mensal) para tabelas com milhões de linhas.
- **Índices GIN**: busca full-text em cards via `pg_trgm`.
- **Connection pooling**: usar PgBouncer (incluído no Supabase Cloud) em modo `transaction`.
- **Read replicas**: queries de relatório podem ser direcionadas a réplica read-only.
- **Edge Functions**: automações pesadas rodam em Deno Edge Functions, não no banco.
