# 🚀 Guia Completo — Do Zero ao Trello Rodando no Windows

> **Para quem nunca programou.** Siga cada passo na ordem. Não pule nenhum.

---

## 📋 O QUE VAMOS FAZER

1. Instalar as ferramentas necessárias
2. Criar o banco de dados local (Supabase)
3. Aplicar o sistema (migrations)
4. Testar que tudo funciona
5. Colocar online (Supabase Cloud) — opcional

**Tempo estimado:** 1h a 2h na primeira vez.

---

# PARTE 1 — INSTALANDO AS FERRAMENTAS

---

## PASSO 1 — Instalar o VS Code (editor de texto)

1. Abra o navegador e acesse: **https://code.visualstudio.com**
2. Clique no botão azul **"Download for Windows"**
3. Abra o arquivo baixado e clique **Próximo → Próximo → Instalar**
4. Marque a opção **"Adicionar ao PATH"** se aparecer
5. Clique em **Concluir**

✅ Pronto. VS Code instalado.

---

## PASSO 2 — Instalar o Docker Desktop

O Docker vai rodar o banco de dados na sua máquina sem instalar nada diretamente no Windows.

1. Acesse: **https://www.docker.com/products/docker-desktop**
2. Clique em **"Download for Windows"**
3. Abra o instalador e clique em **OK → Finish**
4. **Reinicie o computador** quando pedir
5. Após reiniciar, o Docker vai abrir automaticamente
6. Aceite os termos e aguarde o ícone da baleia 🐳 aparecer na barra de tarefas

> ⚠️ Se aparecer erro sobre "WSL 2", clique no link que o Docker mostrar e siga as instruções. É uma atualização do Windows. Depois reinicie novamente.

✅ Pronto quando a baleia aparecer verde/estável.

---

## PASSO 3 — Instalar o Node.js

1. Acesse: **https://nodejs.org**
2. Clique no botão **"LTS"** (versão recomendada, à esquerda)
3. Abra o instalador → Próximo → Aceitar → Instalar
4. Deixe todas as opções padrão marcadas

✅ Pronto. Node instalado.

---

## PASSO 4 — Instalar o Supabase CLI

O Supabase CLI é o programa que vai criar e gerenciar o banco de dados.

1. Pressione **Windows + R**, digite `powershell` e pressione Enter
2. Na janela preta que abriu, copie e cole o comando abaixo e pressione Enter:

```powershell
winget install Supabase.CLI
```

3. Aguarde a instalação terminar (pode demorar 1-2 minutos)
4. **Feche e abra o PowerShell novamente**
5. Digite para confirmar que instalou:

```powershell
supabase --version
```

Deve aparecer algo como: `1.x.x`

> ⚠️ Se `winget` não funcionar, baixe manualmente em:
> https://github.com/supabase/cli/releases
> Baixe o arquivo `supabase_windows_amd64.exe`, renomeie para `supabase.exe`
> e coloque em `C:\Windows\System32\`

✅ Pronto. Supabase CLI instalado.

---

# PARTE 2 — CRIANDO O PROJETO

---

## PASSO 5 — Criar a pasta do projeto

1. Abra o **Explorador de Arquivos** do Windows
2. Vá até a pasta onde quer guardar o projeto (ex: `Documentos`)
3. Crie uma nova pasta chamada: `meu-trello`
4. Abra o VS Code
5. Clique em **File → Open Folder** e selecione a pasta `meu-trello`
6. Clique em **Terminal → New Terminal** no menu do VS Code

Uma janela preta vai aparecer na parte de baixo do VS Code. É aqui que você vai digitar os próximos comandos.

---

## PASSO 6 — Extrair os arquivos do sistema

1. Localize o arquivo **`trello-supabase.tar`** que você baixou anteriormente
2. Clique com o botão direito → **Extrair aqui** (use o WinRAR ou 7-Zip)
   - Se não tiver WinRAR: https://www.rarlab.com/download.htm
3. Mova o conteúdo da pasta extraída para dentro de `meu-trello`

A estrutura deve ficar assim:
```
meu-trello/
└── supabase/
    ├── config.toml
    ├── seed.sql
    └── migrations/
        ├── 001_extensions_and_users.sql
        ├── 002_workspaces.sql
        ├── 003_boards_lists_cards.sql
        ├── 004_card_details.sql
        ├── 005_activity_notifications_automations.sql
        ├── 006_rls_policies.sql
        └── 007_storage_and_views.sql
```

---

## PASSO 7 — Inicializar o Supabase local

No terminal do VS Code (aquela janela preta na parte de baixo), digite:

```bash
supabase init
```

> Se perguntar algo, pressione Enter para aceitar o padrão.

Vai criar alguns arquivos na pasta. Isso é normal.

---

## PASSO 8 — Substituir o config.toml

O arquivo `config.toml` que veio no projeto é melhor que o gerado automaticamente.

1. Dentro de `meu-trello`, existe agora uma pasta chamada `supabase`
2. Abra o arquivo `supabase/config.toml` no VS Code
3. **Substitua todo o conteúdo** pelo conteúdo do `config.toml` que veio no pacote

---

## PASSO 9 — Colocar as migrations no lugar certo

As migrations do pacote devem estar em `supabase/migrations/`. Verifique que os 7 arquivos `.sql` estão lá dentro.

Se estiverem em outro lugar, mova-os para `supabase/migrations/`.

---

# PARTE 3 — LIGANDO O BANCO DE DADOS

---

## PASSO 10 — Iniciar o Supabase local

> ⚠️ O Docker **precisa estar aberto e rodando** (ícone da baleia na barra de tarefas).

No terminal do VS Code:

```bash
supabase start
```

**Aguarde.** Na primeira vez vai baixar vários arquivos (pode levar 5-15 minutos dependendo da internet). Você vai ver várias linhas passando — isso é normal.

Quando terminar, vai aparecer algo parecido com isso:

```
API URL: http://localhost:54321
DB URL: postgresql://postgres:postgres@localhost:54322/postgres
Studio URL: http://localhost:54323
Anon key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Service role key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

📋 **COPIE E SALVE ESSES VALORES** em um bloco de notas. Você vai precisar deles.

✅ Supabase rodando localmente!

---

## PASSO 11 — Aplicar as migrations (criar o banco)

Ainda no terminal:

```bash
supabase db push
```

Vai aparecer uma lista das 7 migrations sendo aplicadas. Ao final deve mostrar:

```
Finished supabase db push.
```

> ⚠️ Se aparecer algum erro vermelho, copie a mensagem e me envie. Vou ajudar.

✅ Banco de dados criado com todas as tabelas!

---

## PASSO 12 — Acessar o painel visual (Studio)

Abra o navegador e acesse: **http://localhost:54323**

Vai abrir o **Supabase Studio** — o painel de controle do banco de dados.

Explore:
- **Table Editor** → veja todas as tabelas criadas
- **SQL Editor** → onde você pode rodar os relatórios
- **Authentication** → onde vão aparecer os usuários

---

## PASSO 13 — Criar o usuário MASTER

1. No Studio, clique em **Authentication** no menu da esquerda
2. Clique em **Add user → Create new user**
3. Preencha:
   - Email: `master@suaempresa.com` (ou qualquer e-mail seu)
   - Password: uma senha forte
   - Marque **"Auto Confirm User"**
4. Clique em **Create User**

Agora vá no **SQL Editor** (menu esquerdo) e rode:

```sql
UPDATE public.profiles
SET global_role = 'MASTER'
WHERE id = (
  SELECT id FROM auth.users WHERE email = 'master@suaempresa.com' LIMIT 1
);
```

Clique em **Run** (ou Ctrl+Enter).

Deve aparecer: `1 row affected` ✅

---

## PASSO 14 — Aplicar o seed (dados de exemplo)

No SQL Editor do Studio, clique em **New Query**, cole o conteúdo do arquivo `seed.sql` e clique em **Run**.

> Lembre de trocar `master@suaempresa.com` pelo e-mail que você usou.

✅ Agora você tem um workspace, board, listas e cartão de exemplo criados!

---

## PASSO 15 — Testar um relatório

No SQL Editor, cole esta query e clique em Run:

```sql
SELECT card_title, board_name, list_name, card_status, assignees
FROM public.v_cards_full;
```

Deve aparecer o cartão de exemplo criado pelo seed. ✅

---

## PASSO 16 — Criar o arquivo de variáveis de ambiente

Na pasta `meu-trello`, crie um arquivo chamado **`.env.local`** (com o ponto na frente) e coloque:

```env
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=cole_aqui_o_anon_key_do_passo_10
SUPABASE_SERVICE_ROLE_KEY=cole_aqui_o_service_role_key_do_passo_10
```

Substitua os valores pelos que você salvou no Passo 10.

---

# PARTE 4 — COLOCAR ONLINE (Supabase Cloud)

> Faça isso quando o sistema local estiver funcionando.

---

## PASSO 17 — Criar conta no Supabase Cloud

1. Acesse: **https://supabase.com**
2. Clique em **Start your project**
3. Entre com sua conta GitHub (crie uma em https://github.com se não tiver)
4. Clique em **New Project**
5. Preencha:
   - **Name:** meu-trello
   - **Database Password:** crie uma senha forte e **SALVE ela**
   - **Region:** South America (São Paulo)
6. Clique em **Create new project**
7. Aguarde 2-3 minutos enquanto o projeto é criado

---

## PASSO 18 — Pegar as chaves do Cloud

1. No painel do Supabase Cloud, clique em **Settings** (engrenagem, menu esquerdo)
2. Clique em **API**
3. Copie e salve:
   - **Project URL** (ex: `https://xyzxyz.supabase.co`)
   - **anon public** key
   - **service_role** key

---

## PASSO 19 — Conectar o CLI ao Cloud

No terminal do VS Code:

```bash
supabase login
```

Vai abrir o navegador pedindo para autorizar. Clique em **Authorize**.

Depois:

```bash
supabase link --project-ref SEU_PROJECT_REF
```

O `SEU_PROJECT_REF` é aquele código no URL do seu projeto Cloud.
Ex: se a URL for `https://abcdefgh.supabase.co`, o ref é `abcdefgh`.

Quando pedir a senha do banco, coloque a senha que você criou no Passo 17.

---

## PASSO 20 — Enviar o banco para o Cloud

```bash
supabase db push
```

As mesmas 7 migrations vão ser aplicadas agora no Cloud. Aguarde terminar.

✅ **Seu banco está no ar!**

---

## PASSO 21 — Criar o usuário MASTER no Cloud

1. Acesse o painel do seu projeto em **https://supabase.com/dashboard**
2. Clique em **Authentication → Add user**
3. Crie o usuário MASTER igual ao Passo 13
4. Vá em **SQL Editor** e rode o mesmo UPDATE do Passo 13

---

## PASSO 22 — Atualizar o .env.local para produção

```env
SUPABASE_URL=https://SEU_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=cole_o_anon_key_do_cloud
SUPABASE_SERVICE_ROLE_KEY=cole_o_service_role_key_do_cloud
```

---

# ✅ RESUMO — O QUE VOCÊ TEM AGORA

| O quê | Onde acessar |
|-------|-------------|
| Banco local (dev) | http://localhost:54323 |
| Banco online (prod) | https://supabase.com/dashboard |
| Painel visual das tabelas | Studio → Table Editor |
| Rodar relatórios | Studio → SQL Editor |
| Gerenciar usuários | Studio → Authentication |
| Arquivos do relatório | pasta `reports/executive_reports.sql` |

---

# 🆘 PROBLEMAS COMUNS

**"supabase: command not found"**
→ Feche e abra o terminal novamente. Se persistir, reinicie o computador.

**"Cannot connect to Docker"**
→ Abra o Docker Desktop e aguarde a baleia ficar estável antes de rodar `supabase start`.

**"port already in use"**
→ Algum programa está usando a porta 54321. Reinicie o Docker Desktop.

**Erro vermelho nas migrations**
→ Copie a mensagem de erro completa e me envie. Vou resolver.

**"WSL 2 installation is incomplete"**
→ Acesse https://aka.ms/wsl2kernel, baixe e instale a atualização, depois reinicie.

---

# 📞 PRÓXIMOS PASSOS

Com o banco funcionando, o próximo passo é criar o **frontend** (a tela visual do Trello).
As opções mais populares são:
- **Next.js** (React) — recomendado para projetos sérios
- **Nuxt** (Vue.js) — alternativa mais simples

Me avise quando chegar nessa etapa!
