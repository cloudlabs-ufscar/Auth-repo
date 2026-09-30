# Pipeline CI/CD e Automação Ansible

Este documento descreve a automação de entrega contínua (CI/CD) implementada via GitHub Actions e o playbook do Ansible responsável por provisionar a stack do IAM.

---

## 1. O Workflow do GitHub Actions ([`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml))

O workflow foi renomeado de `blank.yml` para `deploy.yml` e totalmente reescrito para fornecer um deploy seguro, resiliente e autônomo.

### Gatilhos de Disparo
```yaml
on:
  push:
    branches: [ "main" ]
  workflow_dispatch:
```
* **`push` na branch `main`:** Qualquer alteração mergeada ou commitada diretamente na `main` dispara o deploy em produção automaticamente.
* **`workflow_dispatch`:** Permite que os administradores disparem o deploy manualmente pela interface gráfica do GitHub (**Actions > Deploy IAM > Run workflow**) a qualquer momento, sem necessidade de novo commit.
* **Remoção de `pull_request`:** O gatilho de pull request foi removido propositalmente para evitar que forks ou PRs não revisados executem conexões SSH contra a infraestrutura do laboratório.

---

## 2. Fluxo de Conexão e Execução no Nó Bastion (Nimbus)

O GitHub Actions conecta-se ao servidor bastion **Nimbus** (`nimbus.dc.ufscar.br:2002`), que tem rota direta e chave autorizada para orquestrar o IAM e os clusters através da rede interna gerenciada pelo MAAS (`idp.maas`).

```mermaid
sequenceDiagram
    autonumber
    participant GHA as GitHub Actions Runner
    participant Nimbus as Nó Bastion (Nimbus :2002)
    participant IAM as Servidor IAM (idp.maas)

    GHA->>Nimbus: SSH Connect (appleboy/ssh-action v1.2.5) com secrets HOST, USERNAME, KEY
    Note over Nimbus: Injeta KEYCLOAK_GITHUB_CLIENT_ID e SECRET nas variáveis de ambiente da sessão
    Nimbus->>Nimbus: Valida repositório em ~/repos/Auth-repo (Clona se não existir)
    Nimbus->>Nimbus: git fetch origin main && git reset --hard origin/main
    Nimbus->>IAM: Executa ansible-playbook via SSH (ubuntu@idp.maas)
    Note over IAM: Executa tasks:<br/>1. Instala pacotes/Docker<br/>2. Atualiza configs e schema.json<br/>3. Aplica Docker Compose atualizado
    IAM-->>Nimbus: Ansible Recap: ok=X changed=Y failed=0
    Nimbus-->>GHA: Deploy concluído com status 0
```

---

## 3. O Script Remoto de Deploy

O bloco de execução dentro do workflow realiza etapas preventivas de segurança antes de chamar o Ansible:

```bash
set -e

echo "[*] Navigating to repository directory..."
mkdir -p ~/repos
if [ ! -d ~/repos/Auth-repo/.git ]; then
  echo "[*] Cloning repository for the first time..."
  git clone https://github.com/cloudlabs-ufscar/Auth-repo.git ~/repos/Auth-repo
fi

cd ~/repos/Auth-repo

EXPECTED_URL="https://github.com/cloudlabs-ufscar/Auth-repo.git"
CURRENT_URL=$(git remote get-url origin)

if [ "$CURRENT_URL" != "$EXPECTED_URL" ]; then
  echo "[!] Remote URL ($CURRENT_URL) does not match expected repository!"
  exit 1
fi

echo "[*] Fetching and resetting to origin/main..."
git fetch origin main
git reset --hard origin/main

echo "[*] Repository updated successfully."

echo "[*] Navigating to Ansible scripts..."
cd ~/repos/Auth-repo/scripts/ansible-iam

EXTRA_VARS=""
if [ -n "$KEYCLOAK_GITHUB_CLIENT_ID" ]; then
  EXTRA_VARS="$EXTRA_VARS -e github_client_id=$KEYCLOAK_GITHUB_CLIENT_ID"
fi
if [ -n "$KEYCLOAK_GITHUB_CLIENT_SECRET" ]; then
  EXTRA_VARS="$EXTRA_VARS -e github_client_secret=$KEYCLOAK_GITHUB_CLIENT_SECRET"
fi

echo "[*] Executing Ansible IAM playbook..."
ansible-playbook -i inventory/inventory tasks/first-deploy.yml $EXTRA_VARS

echo "[*] IAM deployment completed successfully!"
```

### Principais Salvaguardas do Script:
1. **Auto-Clone Resiliente:** Se o repositório ainda não foi clonado no Nimbus (primeira execução), o script roda o `git clone` automaticamente.
2. **Validação de URL Remota:** Garante que o diretório `~/repos/Auth-repo` aponta estritamente para `cloudlabs-ufscar/Auth-repo.git`, evitando que scripts sejam executados contra forks errados.
3. **Reset Limpo (`git reset --hard origin/main`):** Garante que qualquer alteração manual temporária deixada na máquina local seja descartada, assegurando que o servidor execute rigorosamente o código aprovado no Git.
4. **Construção Segura de `EXTRA_VARS`:** Só passa `-e github_client_id=...` se as variáveis tiverem sido realmente injetadas no ambiente.
5. **Timeout Estendido (`command_timeout: 20m`):** Previne que o client SSH aborte a execução no meio do download de imagens Docker ou tarefas do Ansible.

---

## 4. Estrutura do Papel Ansible (`ansible-iam`)

O provisionamento segue a estrutura padrão de roles do Ansible:

```text
scripts/ansible-iam/
├── ansible.cfg                          # remote_user = root, host_key_checking = False
├── inventory/
│   └── inventory                        # Host alvo: idp.maas sob o grupo [iam]
├── tasks/
│   └── first-deploy.yml                 # Playbook de entrada incluindo a role deploy
└── roles/
    └── deploy/
        ├── defaults/
        │   └── main.yml                 # Fallbacks vazios para as credenciais
        ├── vars/
        │   └── paths.yml                # Caminhos no sistema de arquivos (/opt/iam, etc.)
        ├── files/
        │   ├── schema-keycloak.json     # 18 grupos, clients OIDC e IdP
        │   ├── schema-openfga-1.json    # Tuplas de autorização ReBAC
        │   ├── haproxy.cfg              # Configuração do proxy reverso
        │   └── keycloak-openfga-event-publisher.jar # Plugin SPI compilado
        ├── templates/
        │   ├── docker-compose.yml.j2    # Stack Docker parametrizada
        │   └── renew-cert.sh.j2         # Script de cron para renovação Let's Encrypt
        └── tasks/
            ├── main.yml                 # Ponto de entrada da role
            ├── install-packages.yml     # Docker, Certbot, dependências do sistema
            ├── copy-archives.yml        # Distribuição de arquivos e templates
            ├── configure-tls.yml        # Geração e montagem do haproxy.pem
            └── deploy-iam.yml           # Execução do community.docker.docker_compose_v2
```

---

## 5. Gerenciamento de Segredos no GitHub Actions

Para manter o repositório público ou compartilhado sem vazar dados sensíveis, as seguintes variáveis devem estar configuradas em **Settings > Secrets and variables > Actions**:

| Nome do Segredo | Descrição | Exemplo de Valor |
| :--- | :--- | :--- |
| `HOST` | Endereço do host bastion | `nimbus.dc.ufscar.br` |
| `PORT` | Porta SSH do host bastion | `2002` |
| `USERNAME` | Usuário SSH no Nimbus | `iam` |
| `KEY` | Chave privada SSH para acesso à Nimbus | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `KEYCLOAK_GITHUB_CLIENT_ID` | Client ID do OAuth App do GitHub | `Ov23lio0wgRauWBYHDNO` |
| `KEYCLOAK_GITHUB_CLIENT_SECRET` | Client Secret gerado no GitHub | `a1b2c3d4...` |

*(Nota: Os nomes das secrets utilizam o prefixo `KEYCLOAK_GITHUB_*` em conformidade com as regras do GitHub, que proíbem variáveis personalizadas começando com `GITHUB_`).*

---

## 6. Evolução Zero-Trust: Federação OIDC & Topologias de Deploy

Para eliminar completamente arquivos estáticos de token (`openbao-token`) e secrets fixos no GitHub:

### 6.1 Autenticação Dinâmica via GitHub Actions OIDC
1. O GitHub Actions emite um token OIDC JWT assinado pela autoridade oficial do GitHub (`https://token.actions.githubusercontent.com`).
2. O OpenBao valida a assinatura das chaves JWKS públicas do GitHub através do **Tinyproxy** restrito no `idp.maas:8888`.
3. Uma vez validada a claim de repositório (`cloudlabs-ufscar/*`), o OpenBao gera um token efêmero de 15 minutos com a política restrita `iam-reader`.
4. Os playbooks consomem credenciais dinamicamente via `http://vault.maas:8200` e o token expira automaticamente após a execução.

### 6.2 Topologias de Deploy: Bastion Nimbus vs. Deploy Direto no `idp.maas`
- **Opção A (Via Bastion Nimbus - Implementação Atual):**
  - O GitHub Actions conecta no Nimbus (`nimbus.dc.ufscar.br:2002`).
  - O Nimbus centraliza a execução de playbooks para o IAM (`idp.maas`) e para os nós do Incus (`inc1-3.maas`).
  - *Vantagem:* Mantém um ponto único de auditoria das automações gerais do datacenter.
- **Opção B (Deploy Direto no `idp.maas` - Evolução Zero-Trust):**
  - O GitHub Actions conecta diretamente na porta 22 do `idp.maas`.
  - O `idp.maas` executa seu próprio deploy local e fala com o OpenBao exclusivamente pela API HTTP (`http://vault.maas:8200`).
  - *Vantagem de Segurança:* Desacoplamento e redução do raio de explosão (*blast radius*). A máquina do IAM **não tem chaves SSH para o servidor do cofre OpenBao**, garantindo que nenhum comprometimento no IAM ou na pipeline possa conceder acesso administrativo aos nós do cofre.
