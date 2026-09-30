# 🔐 Fluxo Detalhado de Autenticação: Keycloak + GitHub + Validação SPI

Este documento apresenta o diagrama de sequência visual e o detalhamento técnico de todas as requisições HTTP e trocas de mensagens entre o **Navegador**, **Keycloak**, **GitHub OAuth / API**, **PostgreSQL** e o **SPI personalizado de validação de organização**.

---

## 📊 Diagrama de Sequência Completo

```mermaid
sequenceDiagram
    autonumber
    actor User as 👤 Usuário (Browser)
    participant KC as 🛡️ Keycloak (:8443)
    participant GH as 🐙 GitHub OAuth (github.com)
    participant GHAPI as 📡 GitHub REST API (api.github.com)
    participant PG as 🗄️ PostgreSQL (Keycloak DB)

    Note over User,KC: FASE 1: Início e Redirecionamento
    User->>KC: GET /realms/cloudlabs/protocol/openid-connect/auth
    KC-->>User: HTTP 200 (Renderiza tela de login com botão "GitHub")
    User->>KC: GET /realms/cloudlabs/broker/github/login
    KC-->>User: HTTP 302 Redirect para github.com/login/oauth/authorize

    Note over User,GH: FASE 2: Autorização e Consentimento no GitHub
    User->>GH: GET /login/oauth/authorize?client_id=...&scope=read:org...
    User->>GH: POST /login (Credenciais + 2FA no GitHub)
    GH-->>User: HTTP 302 Redirect para Keycloak (?code=XYZ&state=ABC)

    Note over User,KC: FASE 3: Callback, Validação SPI e Onboarding
    User->>KC: GET /realms/cloudlabs/broker/github/endpoint?code=XYZ&state=ABC
    KC->>GH: POST https://github.com/login/oauth/access_token
    GH-->>KC: HTTP 200 {"access_token": "gho_...", "scope": "read:org..."}
    KC->>GHAPI: GET https://api.github.com/user
    GHAPI-->>KC: HTTP 200 {"login": "n-qber", "email": "..."}
    
    rect rgb(240, 248, 255)
        Note over KC,PG: Execução do Fluxo "cloudlabs-first-broker-login"
        KC->>PG: INSERT INTO user_entity (Cria o usuário local "n-qber")
        KC->>GHAPI: GET /orgs/cloudlabs-ufscar/members/n-qber (SPI valida a Org)
        GHAPI-->>KC: HTTP 204 No Content (Usuário é membro ativo!)
        KC->>PG: INSERT INTO user_required_actions ("UPDATE_PASSWORD")
    end

    Note over User,KC: FASE 4: Criação da Senha Local e Conclusão
    KC-->>User: HTTP 302 /login-actions/required-action?execution=UPDATE_PASSWORD
    User->>KC: GET /login-actions/required-action (Exibe tela de Definir Senha)
    User->>KC: POST /login-actions/required-action (Submete nova senha)
    KC->>PG: INSERT INTO credential (Grava hash PBKDF2-SHA256)
    KC-->>User: HTTP 302 Redirect com Cookies de Sessão e Tokens OIDC JWT
```

---

## 🔍 Detalhamento Passo a Passo

### 1. Início da Autenticação
* **Requisição 1:** `GET /realms/cloudlabs/protocol/openid-connect/auth`
  * O usuário acessa uma aplicação protegida (Incus Web, dashboard, console) ou a rota de autorização OIDC.
* **Requisição 2:** `GET /realms/cloudlabs/broker/github/login`
  * O usuário clica no botão de login com GitHub. O Keycloak inicializa a sessão temporária de broker e devolve um redirecionamento `HTTP 302` para o GitHub.

### 2. Autenticação no Provedor Externo (GitHub)
* **Requisição 3:** `GET https://github.com/login/oauth/authorize`
  * Parâmetros: `client_id`, `scope=openid user:email read:org`, `redirect_uri` e `state`.
* **Requisição 4:** O usuário preenche usuário, senha e token 2FA no GitHub.
* **Requisição 5:** `GET /realms/cloudlabs/broker/github/endpoint?code=XYZ&state=ABC`
  * O GitHub devolve o navegador para o Keycloak com o código temporário de autorização (`code`).

### 3. Validação no Backchannel e Execução do SPI
* **Requisição 6:** `POST https://github.com/login/oauth/access_token`
  * O Keycloak troca o código temporário pelo token OAuth de acesso (`gho_...`). Com a configuração `storeToken: true`, esse token fica retido no contexto do broker.
* **Requisição 7:** `GET https://api.github.com/user`
  * O Keycloak baixa o perfil básico (`login`, `name`, `email`).
* **Requisição 8:** Execução do fluxo `cloudlabs-first-broker-login`:
  1. Cria o registro local da conta no Postgres (`user_entity`) com `username = "n-qber"`.
  2. O plugin SPI (`GitHubOrgAuthenticator`) executa:
     `GET https://api.github.com/orgs/cloudlabs-ufscar/members/n-qber`
  3. O GitHub responde `HTTP 204 No Content` (confirmação oficial de associação à organização).
  4. O plugin adiciona a ação obrigatória `UPDATE_PASSWORD` na conta recém-criada.

### 4. Criação da Senha e Conclusão
* **Requisições 9 e 10:** O usuário é encaminhado para a tela de definição de senha local. Ao submeter a senha:
  - O Keycloak gera o hash seguro `PBKDF2-SHA256` (27.500 iterações).
  - Persiste a credencial no banco local.
* **Requisição 11:** O usuário é autenticado com sucesso e recebe a sessão SSO e os tokens JWT finais.

---

> [!TIP]
> A partir desse primeiro login, o usuário tem **soberania de acesso**: pode logar clicando no GitHub ou digitando sua senha diretamente, sem depender da API externa do GitHub no dia a dia.
