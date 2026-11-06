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

> [!NOTE]
> **Por que o `OPENSTACK_CLIENT_SECRET` não precisa estar nas Secrets do GitHub?**
> A integração do OpenStack segue o modelo de segredos dinâmicos via OpenBao (`secret/data/iam/openstack`).
> Durante o deploy executado pelo Ansible (`fetch-secrets.yml`), o playbook lê diretamente a chave `client_secret` do OpenBao na rede interna (`http://vault.maas:8200`) e a repassa ao container do Keycloak via variável de ambiente (`OPENSTACK_CLIENT_SECRET`).
> Portanto, **nenhuma secret adicional precisa ser configurada nas configurações do GitHub Actions**, mantendo a superfície de exposição no GitHub estritamente restrita às credenciais de transporte/SSH.

---

## 6. Evolução Zero-Trust: Federação OIDC & Topologias de Deploy

Para eliminar os arquivos estáticos de token do OpenBao (`openbao-token`, `secret_id` de AppRole)
do caminho da pipeline:

### 6.1 Autenticação Dinâmica via GitHub Actions OIDC
1. O job declara `permissions: id-token: write` e o GitHub Actions emite um JWT assinado pela autoridade oficial do GitHub (`https://token.actions.githubusercontent.com`), com audiência `https://vault.maas:8200`.
2. O JWT vai por SSH até o bastion nimbus, no ambiente do `ansible-playbook` (`ACTIONS_ID_TOKEN`). O `lookup('env', ...)` o lê no controller.
3. O OpenBao valida a assinatura contra o JWKS público do GitHub, alcançado pelo **Tinyproxy** restrito no `idp.maas:8888` (o nó não tem egress direto), e confere `aud`, `bound_issuer` e a claim de repositório (`cloudlabs-ufscar/*`, glob).
4. Validado isso, o OpenBao gera um token de 15 minutos com a política restrita `iam-reader`, usado nas leituras de `secret/iam/*` via `http://vault.maas:8200`.
5. Sem JWT e sem `-e openbao_token`, o playbook **falha antes de ler qualquer segredo**. Não existe fallback automático para AppRole.

> **O que continua estático:** a chave SSH do runner para o nimbus (`secrets.KEY`). Ela autentica
> o transporte, não o OpenBao. Detalhes e o estado de implementação (2026-11-05) em
> [`github-oidc-openbao-flow.md`](github-oidc-openbao-flow.md).

### 6.2 Topologias de Deploy: Bastion Nimbus vs. Deploy Direto no `idp.maas`
- **Opção A (Via Bastion Nimbus - Implementação Atual):**
  - O GitHub Actions conecta no Nimbus (`nimbus.dc.ufscar.br:2002`).
  - O Nimbus centraliza a execução de playbooks para o IAM (`idp.maas`) e para os nós do Incus (`inc1-3.maas`).
  - *Vantagem:* Mantém um ponto único de auditoria das automações gerais do datacenter.
- **Opção B (Deploy Direto no `idp.maas` - Evolução Zero-Trust):**
  - O GitHub Actions conecta diretamente na porta 22 do `idp.maas`.
  - O `idp.maas` executa seu próprio deploy local e fala com o OpenBao exclusivamente pela API HTTP (`http://vault.maas:8200`).
  - *Vantagem de Segurança:* Desacoplamento e redução do raio de explosão (*blast radius*). A máquina do `idp.maas` **não tem chaves SSH para o servidor do cofre OpenBao**, garantindo que nenhum comprometimento no IAM ou na pipeline possa conceder acesso administrativo aos nós do cofre.

## 7. Atualização de Dependências (Renovate)

As imagens do stack e a versão do OpenBao ficam pinadas no repositório; o Renovate abre PR
quando sai versão nova. Ele **nunca** faz push em `main` — só abre PR, que passa pelo mesmo
caminho de revisão.

- Workflow: [`.github/workflows/renovate.yml`](../../.github/workflows/renovate.yml) — roda
  semanalmente (segunda, 06:00 UTC) e por `workflow_dispatch`.
- Configuração: [`renovate.json`](../../renovate.json).
- Token: usa o secret `RENOVATE_TOKEN` se existir; senão cai no `GITHUB_TOKEN` do workflow
  (que já tem `contents: write` + `pull-requests: write`). PRs abertos pelo `GITHUB_TOKEN`
  **não** disparam outros workflows — o deploy só acontece quando alguém faz o merge.

O que é monitorado:

| Origem | Como |
|--------|------|
| `haproxy`, `postgres`, `openfga/openfga`, `quay.io/keycloak/keycloak` | regex manager em `roles/deploy/templates/docker-compose.yml.j2` (o arquivo é Jinja, então o manager nativo de Docker não enxerga) |
| `openbao_version` | regex manager em `roles/openbao/defaults/main.yml`, datasource `github-releases` de `openbao/openbao` |
| `actions/*` e actions de terceiros | datasource `github-actions` (padrão do `config:recommended`) |

Regras deliberadas:

- **`postgres` fica fora do Renovate** (`enabled: false`): o tag `16` já flutua
  dentro do major e pega os patches sozinho; um major novo exige migração
  planejada (o PG14→16 foi feito à mão, com dump/restore e janela de rollback).
- **Keycloak major** vem em PR próprio, com label `keycloak`, porque migração de schema
  exige janela e backup.
- **OpenBao** vem com label `openbao`; o role se recusa a rebaixar versão
  (`assert` em `roles/openbao/tasks/main.yml`).

