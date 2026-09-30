# CloudLabs UFSCar - Infraestrutura de IAM e Autorização (Auth-repo)

Repositório central de **Infraestrutura como Código (IaC)**, automação Ansible, pipelines CI/CD e extensões SPI para a stack de **Identidade, Autenticação e Controle de Acesso (IAM)** do laboratório **CloudLabs - UFSCar**.

---

## 🏛️ Componentes da Stack

* **Keycloak 25 (OIDC IdP):** Provedor de identidade centralizado para os clusters **Cirrus** (Incus) e **Stratus** (OpenStack).
* **OpenFGA v1.5.5 (Fine-Grained Authorization):** PDP (Policy Decision Point) baseado no modelo ReBAC (Relationship-Based Access Control) do Google Zanzibar.
* **OpenBao 2.1.0 HA (Raft Cluster):** Gestão centralizada de segredos dinâmicos e Root of Trust / PKI interna (`vault.maas`, `vault2.maas`, `vault3.maas`).
* **HAProxy 2.8:** Proxy reverso com terminação TLS (certificados Let's Encrypt para `cumulus.dc.ufscar.br`).
* **PostgreSQL:** Bancos de dados dedicados para o Keycloak e OpenFGA em containers isolados.
* **Plugins SPI:**
  * [`keycloak-github-org-validator.jar`](scripts/ansible-iam/roles/deploy/files/keycloak-github-org-validator.jar): Validação estrita de associação à organização GitHub `cloudlabs-ufscar` no primeiro login com obrigatoriedade de senha local (`UPDATE_PASSWORD`).
  * [`keycloak-openfga-event-publisher.jar`](scripts/ansible-iam/roles/deploy/files/keycloak-openfga-event-publisher.jar): Sincronização em tempo real de criação de usuários e atribuição de grupos para tuplas no OpenFGA.

---

## 📂 Estrutura do Repositório

```text
.
├── .github/
│   └── workflows/
│       └── deploy.yml              # Pipeline CI/CD para deploy remoto via SSH e Ansible
├── Documentos/                     # Documentação centralizada do projeto
│   ├── IAM/                        # Guias de arquitetura, manuais operacionais e postmortems
│   │   ├── README.md               # Índice detalhado da documentação IAM
│   │   ├── architecture-overview.md
│   │   ├── keycloak-openfga-integration.md
│   │   ├── openbao-secrets-management.md
│   │   ├── github-federation-and-onboarding.md
│   │   ├── fluxo-autenticacao.md   # Passo a passo técnico requisição por requisição
│   │   ├── fluxo-autenticacao.html # Diagrama sequencial interativo (Mermaid standalone)
│   │   ├── github-oidc-openbao-flow.md   # Federação Zero-Trust GitHub OIDC + OpenBao
│   │   ├── fluxo-github-oidc-openbao.html # Diagrama sequencial interativo OIDC + OpenBao
│   │   ├── ansible-bootstrap-and-scaleout.md # Setup inicial (Day 0) e expansão de nós/racks (Day 2)
│   │   ├── incus-auth-and-authorization.md   # Autenticação CLI vs Web UI & OpenFGA ReBAC
│   │   ├── fluxo-incus-auth-fga.html         # Diagrama interativo de AuthN/AuthZ no Incus
│   │   ├── plugin-keycloak-openfga-event-publisher.md # Plugin SPI de sincronização Keycloak -> OpenFGA
│   │   ├── cicd-and-deployment.md
│   │   └── troubleshooting-and-postmortems.md
│   ├── Politicas/                  # Políticas internas de segurança, DNS, VPN e CA
│   └── Discussoes/                 # Discussões técnicas e estudos de viabilidade anteriores
└── scripts/
    ├── ansible-iam/                # Playbooks e roles de deploy do Keycloak, OpenFGA e OpenBao
    │   └── roles/deploy/files/     # Schemas JSON e plugins SPI (.jar)
    └── ansible-lb/                 # Automação de proxy reverso e balanceamento
```

---

## 📚 Documentação Recomendada

Para detalhes aprofundados sobre arquitetura, fluxos e segurança, consulte:

1. [**Índice Geral de IAM**](Documentos/IAM/README.md)
2. [**Visão Geral da Arquitetura**](Documentos/IAM/architecture-overview.md)
3. [**Autenticação e Autorização no Incus (CLI vs Web UI & OpenFGA ReBAC)**](Documentos/IAM/incus-auth-and-authorization.md)
4. [**Plugin SPI Keycloak-OpenFGA Event Publisher**](Documentos/IAM/plugin-keycloak-openfga-event-publisher.md)
5. [**Gestão de Segredos & PKI no OpenBao**](Documentos/IAM/openbao-secrets-management.md)
6. [**Federação Zero-Trust: GitHub Actions OIDC + OpenBao**](Documentos/IAM/github-oidc-openbao-flow.md)
7. [**Bootstrap Ansible (Day 0) e Expansão de Servidores / Racks (Day 2)**](Documentos/IAM/ansible-bootstrap-and-scaleout.md)
8. [**Federação GitHub & Onboarding Híbrido**](Documentos/IAM/github-federation-and-onboarding.md)
9. [**Diagrama Interativo do Fluxo de Autenticação (.html)**](Documentos/IAM/fluxo-autenticacao.html) *(abra diretamente no navegador)*
10. [**Diagrama Interativo de AuthN/AuthZ Incus + FGA (.html)**](Documentos/IAM/fluxo-incus-auth-fga.html) *(abra diretamente no navegador)*
11. [**Diagrama Interativo do Fluxo OIDC OpenBao (.html)**](Documentos/IAM/fluxo-github-oidc-openbao.html) *(abra diretamente no navegador)*
12. [**Troubleshooting e Postmortems de Produção**](Documentos/IAM/troubleshooting-and-postmortems.md)

---

## 🚀 Deploy Contínuo (CI/CD)

O deploy é disparado automaticamente a cada `git push` na branch `main` via [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

Durante a execução da pipeline:
1. Conecta-se com segurança ao host de gerência via chave SSH privada.
2. Atualiza o repositório local.
3. Executa a role Ansible que autentica no **OpenBao Raft HA** para extrair dinamicamente credenciais de banco e chaves de API sem expor senhas em texto puro.
4. Gera as configurações parametrizadas e atualiza os containers via Docker Compose.