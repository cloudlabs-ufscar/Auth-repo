# Documentação da Infraestrutura IAM (Keycloak, OpenFGA, OpenBao, Incus & CI/CD)

Bem-vindo à documentação técnica detalhada das alterações, correções e arquitetura da infraestrutura de Identidade e Acesso (IAM) do **CloudLabs - UFSCar**.

Este conjunto de documentos consolida todo o processo de auditoria, sincronização de Infrastructure as Code (IaC), correções de bugs, segurança de credenciais, autoridade de certificação interna (PKI Root CA) e automação de deploy contínuo realizado no repositório [`Auth-repo`](https://github.com/cloudlabs-ufscar/Auth-repo).

---

## 🗺️ Índice da Documentação

A documentação está dividida em 5 módulos estruturados:

1. [**Arquitetura Geral do Sistema**](architecture-overview.md)
   * Visão sistêmica dos componentes (`Keycloak`, `OpenFGA`, `OpenBao`, `HAProxy`, `PostgreSQL`, `Incus`, `Nimbus`).
   * Fluxos de autenticação OIDC (Web UI e CLI via Device Code Grant).
   * Modelo de controle de acesso baseado em relacionamentos (ReBAC).
   * Segmentação computacional: **Cirrus** (Incus) e **Stratus** (OpenStack).

2. [**Integração Keycloak e OpenFGA**](keycloak-openfga-integration.md)
   * Estrutura dos 18 grupos planos vs. grupos aninhados (justificativa técnica detalhada).
   * Configuração dos clients `incus-cirrus` e fluxos de autenticação.
   * Funcionamento do plugin SPI `keycloak-openfga-event-publisher`.
   * Mapeamento de tuplas e isolamento por projeto no OpenFGA.

3. [**Pipeline CI/CD e Automação Ansible**](cicd-and-deployment.md)
   * Workflow do GitHub Actions (`.github/workflows/deploy.yml`).
   * Fluxo de conexão SSH com o nó bastion (Nimbus) e máquina alvo (`idp.maas`).
   * Injeção dinâmica de segredos (`KEYCLOAK_GITHUB_CLIENT_ID` e `SECRET`).
   * Estrutura do playbook Ansible e idempotência.

4. [**Troubleshooting e Análise de Falhas Resolvidas**](troubleshooting-and-postmortems.md)
   * *Postmortem 1*: Loop de reinício no container `migrate` e timeout no Docker Compose.
   * *Postmortem 2*: Erro de chave pública SSH (`root@200.18.99.87: Permission denied`).
   * *Postmortem 3*: Restrição de nomes de secrets no GitHub Actions (`GITHUB_*`).
   * *Postmortem 4*: Identificação de usuários no Incus (`oidc.claim`: `email` vs. `preferred_username` vs. `sub`).

5. [**Gestão Centralizada de Segredos & PKI com OpenBao**](openbao-secrets-management.md)
   * Cluster de Alta Disponibilidade (HA) de 3 nós com Raft Storage (`vault.maas`, `vault2.maas`, `vault3.maas`).
   * Padrão de implantação *air-gapped* via Ansible e pacote nativo `.deb`.
   * Inicialização Shamir e serviço de auto-unseal no systemd em todos os membros.
   * Root of Trust: Engine PKI habilitada e emissão da `CloudLabs Internal Root CA` (validade 2026-2041).
   * Política de Menor Privilégio (`iam-reader`) para leitura de credenciais do OpenFGA.
   * Integração dinâmica com o cluster Incus (Cirrus), eliminando credenciais em texto plano.

6. [**Federação GitHub, Onboarding e Autenticação Híbrida**](github-federation-and-onboarding.md)
   * Onboarding com gatekeeper: validação de elegibilidade na organização `cloudlabs-ufscar`.
   * Criação e persistência do usuário no banco local do Keycloak com senha obrigatória (`UPDATE_PASSWORD`).
   * Autonomia operacional: login rotineiro local independente de serviços externos.
   * Especificação do plugin SPI `keycloak-github-org-validator`.

7. [**Fluxo Detalhado de Autenticação (Diagrama Sequencial e Interativo)**](fluxo-autenticacao.md)
   * Detalhamento requisição a requisição: fases 1 a 4, 19 passos HTTP com payloads, query params, tokens e cookies.
   * [**Versão Interativa (.html)**](fluxo-autenticacao.html): Diagrama Mermaid standalone para visualização direta no navegador (com renderizador automático, dark mode e zoom).

---

## 🏗️ Visão Geral da Arquitetura

O diagrama abaixo ilustra como os componentes do repositório interagem entre si, com a autoridade de segredos e com os clusters computacionais do laboratório:

```mermaid
flowchart TD
    subgraph Gestao_Segredos_PKI["Segurança & Root of Trust (OpenBao HA)"]
        BAO_LEAD["vault.maas<br/>OpenBao Leader :8200"]
        BAO_F1["vault2.maas<br/>OpenBao Follower"]
        BAO_F2["vault3.maas<br/>OpenBao Follower"]
        
        BAO_LEAD <-->|Raft Sync :8201| BAO_F1
        BAO_LEAD <-->|Raft Sync :8201| BAO_F2
        
        PKI["PKI Engine: CloudLabs Internal Root CA<br/>Validade: 2026 - 2041"]
        KV["KV-v2 Engine: secret/iam/openfga<br/>Policy: iam-reader"]
        
        BAO_LEAD --- PKI
        BAO_LEAD --- KV
    end

    subgraph Automacao["Automação & Orquestração (Nimbus Bastion)"]
        NIMBUS["Nó Bastion: Nimbus<br/>Ansible Controller"]
        TOKEN["files/openbao-token<br/>(Menor Privilégio)"]
        CA_PUB["files/cloudlabs-ca.crt<br/>(Certificado Público)"]
        
        NIMBUS --> TOKEN
        NIMBUS --> CA_PUB
        NIMBUS -.->|Consulta segredos via API :8200| BAO_LEAD
    end

    subgraph Stack_IAM["Stack de Serviços IAM (idp.maas / Docker Compose)"]
        HAPROXY[HAProxy: 443 / 8443<br/>SSL Termination via Let's Encrypt]
        KC[Keycloak 25: OIDC Identity Provider<br/>Realm: cloudlabs]
        FGA[OpenFGA v1.5.5: PDP ReBAC Service]
        PG_KC[(Postgres Keycloak)]
        PG_FGA[(Postgres OpenFGA)]
        SPI[Keycloak SPI Plugin:<br/>openfga-events-publisher]

        HAPROXY -->|Proxy Reverso :8080| KC
        KC --> PG_KC
        FGA --> PG_FGA
        KC -.->|Carrega extensão| SPI
        SPI -->|Sincroniza eventos de grupo :8080| FGA
    end

    subgraph Computacao_Cirrus["Cluster Cirrus (Incus Containers & VMs)"]
        INC1["inc1-cirrus (inc1.maas)"]
        INC2["inc2-cirrus (inc2.maas)"]
        INC3["inc3-cirrus (inc3.maas)"]
        
        INC1 <-->|Incus Cluster Raft/Dqlite| INC2
        INC2 <-->|Incus Cluster Raft/Dqlite| INC3
        
        INC1 -->|Valida JWT OIDC| KC
        INC1 -->|Consulta Permissão ReBAC| FGA
    end

    subgraph Computacao_Stratus["Cluster Stratus (OpenStack IaaS)"]
        OS_NODES["Nós Stratus (c4, c5, c6)<br/>OpenStack Keystone / Nova / Neutron"]
        OS_NODES -.->|Futura Federação OIDC| KC
    end

    NIMBUS -->|configure-incus.yml: Injeta CA e Segredos| Computacao_Cirrus
    NIMBUS -->|deploy.yml: Provisiona Stack| Stack_IAM
    PKI -.->|Distribuído na Trust Store /etc/ssl/certs| Computacao_Cirrus
    PKI -.->|Distribuído na Trust Store /etc/ssl/certs| Stack_IAM
```

---

## 📌 Resumo dos Arquivos Modificados no Repositório

| Arquivo | Mudança Principal |
| :--- | :--- |
| [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) | Automação completa de deploy via SSH, clone automático, injeção de segredos e timeout de 20m. |
| [`scripts/ansible-iam/inventory/inventory`](../../scripts/ansible-iam/inventory/inventory) | Grupo `[vault]` configurado com o cluster de 3 nós: `vault.maas`, `vault2.maas` e `vault3.maas`. |
| [`scripts/ansible-iam/tasks/deploy-openbao.yml`](../../scripts/ansible-iam/tasks/deploy-openbao.yml) | Playbook de deploy automatizado do cluster OpenBao HA em padrão air-gapped. |
| [`scripts/ansible-iam/roles/openbao/`](../../scripts/ansible-iam/roles/openbao/) | Role completa: instalação `.deb`, template Raft `openbao.hcl`, inicialização Shamir, Raft Join e auto-unseal systemd. |
| [`scripts/ansible-iam/roles/deploy/tasks/fetch-secrets.yml`](../../scripts/ansible-iam/roles/deploy/tasks/fetch-secrets.yml) | Leitura dinâmica e segura de credenciais do cluster OpenBao Raft HA em tempo de execução via token `iam-reader`. |
| [`scripts/ansible-iam/roles/deploy/files/schema-keycloak.json`](../../scripts/ansible-iam/roles/deploy/files/schema-keycloak.json) | 18 grupos planos, client `incus-cirrus` público com Device Flow, segredos parametrizados. |
| [`scripts/ansible-iam/roles/deploy/files/schema-openfga-1.json`](../../scripts/ansible-iam/roles/deploy/files/schema-openfga-1.json) | Tupla administrativa `group:admin-project-admin#member -> server:incus` e mapeamentos por projeto. |
| [`scripts/ansible-iam/roles/deploy/templates/docker-compose.yml.j2`](../../scripts/ansible-iam/roles/deploy/templates/docker-compose.yml.j2) | Correção de healthcheck, remoção de restart loop do `migrate`, injeção dinâmica de segredos via OpenBao. |
| [`scripts/ansible-iam/roles/deploy/defaults/main.yml`](../../scripts/ansible-iam/roles/deploy/defaults/main.yml) | Fallbacks seguros `github_client_id: ""` e `github_client_secret: ""`. |
| [`github-federation-and-onboarding.md`](github-federation-and-onboarding.md) | Documentação completa do fluxo de onboarding com validação de org GitHub e SPI. |
| [`fluxo-autenticacao.md`](fluxo-autenticacao.md) | Detalhamento técnico requisição a requisição com tabelas e diagrama Mermaid. |
| [`fluxo-autenticacao.html`](fluxo-autenticacao.html) | Página HTML standalone com Mermaid interativo (dark theme, pan/zoom) para visualização offline. |
