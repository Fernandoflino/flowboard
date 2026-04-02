# 📦 FlowBoard — Guia de Montagem Final

## Estrutura completa do projeto

```
meu-trello/
│
├── supabase/                        ← BANCO DE DADOS
│   ├── config.toml
│   ├── seed.sql
│   └── migrations/
│       ├── 001_extensions_and_users.sql
│       ├── 002_workspaces.sql
│       ├── 003_boards_lists_cards.sql
│       ├── 004_card_details.sql
│       ├── 005_activity_notifications_automations.sql
│       ├── 006_rls_policies.sql
│       ├── 007_storage_and_views.sql
│       ├── 008_helper_functions.sql
│       └── 009_admin_impersonation_and_views.sql  ← NOVO
│
├── frontend/                        ← TELAS (HTML/CSS/JS)
│   ├── index.html                   ← Página inicial (redireciona)
│   ├── login.html                   ← Login e cadastro
│   ├── css/
│   │   └── style.css                ← Design system completo
│   ├── js/
│   │   └── supabase.js              ← Cliente + utilitários
│   └── pages/
│       ├── dashboard.html           ← Lista de boards
│       ├── kanban.html              ← Quadro Kanban
│       ├── card.html                ← Detalhes do cartão
│       ├── reports.html             ← Relatórios executivos
│       ├── calendar.html            ← Visualização de calendário
│       ├── timeline.html            ← Visualização de timeline
│       ├── members.html             ← Membros do workspace
│       ├── settings.html            ← Configurações
│       ├── profile.html             ← Perfil do usuário
│       └── reset-password.html      ← Redefinir senha
│
└── reports/
    └── executive_reports.sql        ← Queries SQL avançadas
```

---

## ⚡ PASSO ÚNICO antes de abrir as telas

Abra o arquivo `frontend/js/supabase.js` e substitua as duas linhas no topo:

```js
// ANTES (linhas 7 e 8):
const SUPABASE_URL = 'http://localhost:54321';
const SUPABASE_KEY = 'SEU_ANON_KEY_AQUI';

// DEPOIS (coloque seus valores reais):
const SUPABASE_URL = 'http://localhost:54321';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'; // sua anon key
```

O **anon key** aparece quando você roda `supabase start` no terminal.

---

## 🖥️ Como abrir as telas

### Opção A — Abrir direto no navegador (mais simples)
Clique duas vezes em `frontend/index.html`.
> ⚠️ Pode ter problema com CORS em alguns navegadores. Se isso acontecer, use a Opção B.

### Opção B — Servir com um servidor local (recomendado)
No terminal do VS Code, dentro da pasta `frontend/`:

```bash
# Instalar o servidor (uma vez só):
npm install -g serve

# Iniciar:
serve .
```

Vai aparecer: `Serving! → http://localhost:3000`

Abra `http://localhost:3000` no navegador.

---

## 🗺️ Mapa de navegação

```
login.html
    │
    └──► dashboard.html (lista de boards)
              │
              ├──► kanban.html (quadro com drag & drop)
              │         │
              │         └──► card.html (detalhes completos do cartão)
              │
              ├──► reports.html (relatórios + exportar CSV)
              ├──► calendar.html (calendário por data de entrega)
              ├──► timeline.html (timeline por início/entrega)
              ├──► members.html (gerenciar membros)
              ├──► settings.html (configurações do workspace)
              └──► profile.html (perfil do usuário)
```

---

## ✅ Funcionalidades por tela

### login.html
- [x] Login com e-mail e senha
- [x] Cadastro de nova conta
- [x] Recuperação de senha por e-mail
- [x] Redirecionamento automático se já logado

### dashboard.html
- [x] Cards de todos os boards do workspace
- [x] 4 métricas no topo (total, concluídos, em andamento, atrasados)
- [x] Criar novo workspace
- [x] Criar novo board com cor personalizada e listas padrão automáticas
- [x] Trocar de workspace pelo topbar
- [x] Busca global de cartões

### kanban.html
- [x] Listas e cartões em colunas
- [x] Drag & drop de cartões entre listas
- [x] Adicionar cartão inline (Enter para salvar)
- [x] Adicionar nova lista
- [x] Renomear lista com duplo clique
- [x] Arquivar lista
- [x] Filtros por membro, etiqueta e status
- [x] Indicador de atraso (ícone vermelho na data)
- [x] Avatares dos responsáveis no cartão
- [x] Bolinhas de etiquetas coloridas

### card.html
- [x] Editar título (clique direto no texto)
- [x] Editar descrição
- [x] Alterar status (ativo/concluído/arquivado)
- [x] Datas de início e entrega
- [x] Adicionar/remover responsáveis
- [x] Adicionar/remover etiquetas
- [x] Checklists com barra de progresso
- [x] Itens de checklist (marcar/desmarcar/excluir)
- [x] Comentários (criar/editar/excluir)
- [x] Upload de anexos (imagens e arquivos)
- [x] Preview de imagens nos anexos
- [x] Cor de capa
- [x] Campos personalizados (leitura)
- [x] Arquivar cartão

### reports.html
- [x] Filtros por período, board, membro, status
- [x] 4 métricas: total, concluídos, atrasados, tempo médio
- [x] Gráfico de barras por responsável
- [x] Gráfico de barras por board
- [x] Tabela detalhada com todos os cartões
- [x] Exportar para CSV (abre no Excel)

### calendar.html
- [x] Visualização mensal de cartões por data de entrega
- [x] Navegação entre meses
- [x] Destaque de itens atrasados

### timeline.html
- [x] Linha do tempo por data de início/entrega
- [x] Barras relativas à duração das tarefas
- [x] Destaque visual para tarefas atrasadas

### members.html
- [x] Lista de membros com foto e função
- [x] Convidar membro por e-mail
- [x] Alterar função (Admin/Membro/Visualizador)
- [x] Remover membro
- [x] Proteção do MASTER (não aparece botão de remoção)

### settings.html
- [x] Editar nome e descrição do workspace
- [x] Excluir workspace (com confirmação dupla)

### profile.html
- [x] Editar nome
- [x] Upload de foto de perfil
- [x] Alterar senha

---

## 🐛 Se algo não funcionar

| Problema | Causa provável | Solução |
|----------|---------------|---------|
| Tela em branco | anon key errado | Verifique `supabase.js` linha 8 |
| "Failed to fetch" | Supabase não está rodando | `supabase start` no terminal |
| Não redireciona após login | CORS bloqueando | Use `serve .` (Opção B acima) |
| Cartões não aparecem | RLS bloqueando | Verifique se o usuário é membro do workspace |
| Upload não funciona | Bucket não criado | Execute a migration 007 novamente |
