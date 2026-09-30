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
3. [**Gestão de Segredos & PKI no OpenBao**](Documentos/IAM/openbao-secrets-management.md)
4. [**Federação GitHub & Onboarding Híbrido**](Documentos/IAM/github-federation-and-onboarding.md)
5. [**Diagrama Interativo do Fluxo de Autenticação (.html)**](Documentos/IAM/fluxo-autenticacao.html) *(abra diretamente no navegador)*
6. [**Troubleshooting e Postmortems de Produção**](Documentos/IAM/troubleshooting-and-postmortems.md)

---

## 🚀 Deploy Contínuo (CI/CD)

O deploy é disparado automaticamente a cada `git push` na branch `main` via [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

Durante a execução da pipeline:
1. Conecta-se com segurança ao host de gerência via chave SSH privada.
2. Atualiza o repositório local.
3. Executa a role Ansible que autentica no **OpenBao Raft HA** para extrair dinamicamente credenciais de banco e chaves de API sem expor senhas em texto puro.
4. Gera as configurações parametrizadas e atualiza os containers via Docker Compose.