## 1. Introdução

A estruturação dos grupos de hosts é o reflexo físico da nossa topologia de serviços. Para garantir uma administração eficiente e segura, adotamos um modelo que espelha as divisões funcionais dos grupos de utilizadores, mas com uma mecânica de herança distinta.

### 1.1. Herança Explícita

Ao contrário do modelo de utilizadores, em que a herança é lógica e baseada na senioridade, o modelo de hosts utiliza **herança literal e cumulativa**.

Cada máquina (host) deve pertencer explicitamente a todos os níveis da sua árvore hierárquica. Isso garante que comandos de automação, auditorias e, principalmente, as regras de HBAC possam ser aplicadas de forma abrangente (ex: nível `cloudlabs-hosts`) ou granular (ex: nível `incus-stratus`) sem ambiguidade.

---
## 2. Topologia de Grupos de Hosts

A árvore abaixo define a classificação das máquinas bare metal e instâncias críticas da infraestrutura:

```
cloudlabs-hosts
│
├── incus-cluster
│   ├── incus-stratus
│   └── incus-cirrus
│
├── openstack-cluster
│   ├── openstack-cluster1
│   └── openstack-cluster2
│   └── ...
│
├── monitoring-cluster
│
├── iam-cluster
│
└── gateways
```

---
## 3. Políticas de Ciclo de Vida e Provisionamento

Para manter a integridade do inventário no LDAP, as seguintes normas devem ser seguidas no provisionamento de novas máquinas:

### 3.1. Admissão de Hosts

Toda máquina integrada à infraestrutura deve, obrigatoriamente, seguir o fluxo de descendência:

1. Ser vinculada ao grupo raiz `cloudlabs-hosts`.
    
2. Ser vinculada ao grupo de tecnologia (ex: `incus-cluster`).
    
3. Ser vinculada ao grupo de instância específica, se houver (ex: `incus-stratus`).

**Exemplo:** Um novo servidor destinado ao cluster Stratus deve possuir no LDAP a lista de grupos: `[cloudlabs-hosts, incus-cluster, incus-stratus]`.

### 3.2. Criação de Novos Grupos

A expansão da infraestrutura é prevista e deve seguir estes critérios:

- Grupos novos devem ser criados com funções claras e nomes genéricos o suficiente para agrupar máquinas similares.

- Não devem existir grupos de hosts vazios. A criação de um grupo exige a existência de pelo menos um host pronto para admissão.

---
## 4. Definição dos Escopos de Host

| **Grupo**                | **Descrição e Finalidade Técnica**                                                                                                                              |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`cloudlabs-hosts`**    | O supergrupo que engloba toda a infraestrutura. Permite operações globais de manutenção, atualizações de segurança críticas e políticas de acesso transversais. |
| **`incus-cluster`**      | Identifica todos os servidores que rodam o hypervisor Incus, independente do cluster específico.                                                                |
| **`openstack-cluster`**  | Agrupa os nós de controle, computação e storage da arquitetura OpenStack.                                                                                       |
| **`monitoring-cluster`** | Máquinas que hospedam Prometheus, Grafana, Loki e bases de dados temporais.                                                                                     |
| **`iam-cluster`**        | O núcleo de segurança. Contém os servidores do FreeIPA, Keycloak e OpenFGA.                                                                                     |
| **`gateways`**           | Máquinas de borda, gateways de saída e servidores de VPN (ex: Nimbus, Gateway-mgc-vpn).                                                                         |
