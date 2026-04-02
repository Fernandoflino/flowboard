# Variáveis de Ambiente — RF61

## Supabase Local (Docker)

```env
# .env.local
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=<gerado pelo `supabase start`>
SUPABASE_SERVICE_ROLE_KEY=<gerado pelo `supabase start`>

# Storage
SUPABASE_STORAGE_URL=http://localhost:54321/storage/v1

# App
APP_URL=http://localhost:3000
```

## Supabase Cloud / VPS

```env
# .env.production
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<dashboard → Settings → API>
SUPABASE_SERVICE_ROLE_KEY=<dashboard → Settings → API>   # NUNCA expor no frontend
SUPABASE_STORAGE_URL=https://<project-ref>.supabase.co/storage/v1
APP_URL=https://seudominio.com
```

> **ATENÇÃO:** `SERVICE_ROLE_KEY` bypassa RLS completamente.
> Use-o APENAS em funções server-side (Edge Functions, backend).
> Nunca envie para o cliente/browser.

---

# Estratégia de Migração — RF59, RF60

## Local → Cloud (zero retrabalho)

```bash
# 1. Exportar schema atual do local
supabase db dump --local -f schema_backup.sql

# 2. Exportar dados (opcional para migração completa)
supabase db dump --local --data-only -f data_backup.sql

# 3. Vincular ao projeto Cloud
supabase link --project-ref <project-ref>

# 4. Aplicar todas as migrations ao Cloud
supabase db push

# 5. (Opcional) Importar dados
psql $DATABASE_URL < data_backup.sql
```

## Local → VPS (PostgreSQL + PostgREST + GoTrue)

```bash
# A estrutura SQL é padrão PostgreSQL — funciona em qualquer host.
# 1. Provisionar PostgreSQL na VPS
# 2. Aplicar migrations em ordem:
psql $DATABASE_URL < supabase/migrations/001_extensions_and_users.sql
psql $DATABASE_URL < supabase/migrations/002_workspaces.sql
psql $DATABASE_URL < supabase/migrations/003_boards_lists_cards.sql
psql $DATABASE_URL < supabase/migrations/004_card_details.sql
psql $DATABASE_URL < supabase/migrations/005_activity_notifications_automations.sql
psql $DATABASE_URL < supabase/migrations/006_rls_policies.sql
psql $DATABASE_URL < supabase/migrations/007_storage_and_views.sql
# 3. Instalar GoTrue (auth) + PostgREST ou Supabase self-hosted
```

## Estrutura de Pastas

```
trello-supabase/
├── supabase/
│   ├── config.toml               # configuração do projeto Supabase
│   ├── seed.sql                  # dados iniciais
│   └── migrations/
│       ├── 001_extensions_and_users.sql
│       ├── 002_workspaces.sql
│       ├── 003_boards_lists_cards.sql
│       ├── 004_card_details.sql
│       ├── 005_activity_notifications_automations.sql
│       ├── 006_rls_policies.sql
│       └── 007_storage_and_views.sql
├── reports/
│   └── executive_reports.sql
└── docs/
    ├── ARCHITECTURE.md
    └── ENV.md                    ← este arquivo
```
