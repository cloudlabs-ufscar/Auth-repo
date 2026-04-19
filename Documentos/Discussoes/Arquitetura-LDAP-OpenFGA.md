# Arquitetura Revisada: LDAP + OpenFGA (Sem Kerberos)

## 1. Introdução e Justificativa da Revisão

Baseado na arquitetura anteriormente proposta em [Arquitetura-FreeIPA.md](Arquitetura-FreeIPA.md) e na análise consolidada em [Architecture Discussion.md](Architecture%20Discussion.md), este documento propõe uma revisão fundamentada na seguinte questão central:

**"É possível implementar RBAC (Role-Based Access Control) em sistemas Linux utilizando LDAP do FreeIPA sem a necessidade de Kerberos?"**

A resposta a essa pergunta, conforme explorado neste documento, reduz significativamente a complexidade da infraestrutura, permitindo que seja mantida uma abordagem centralizada de autenticação enquanto simplifica a configuração operacional.

Além disso, este documento propõe a integração de **OpenFGA** como solução dedicada de autorização para sistemas web, criando uma separação clara entre:
- **Autenticação:** Identificação de "quem é o usuário" (LDAP + Keycloak)
- **Autorização:** Definição de "o que o usuário pode fazer" (RBAC para Linux + OpenFGA para web)

---

## 2. Análise: LDAP para RBAC em Sistemas Linux

### 2.1 Capacidades Nativas do LDAP

O LDAP, quando integrado com o FreeIPA, oferece suporte robusto para RBAC através de mecanismos implementados em nível de **grupo de usuários** e **policies de controle de acesso**.

#### 2.1.1 Suporte a Grupos e Atributos
O LDAP do FreeIPA permite:

1. **Definição de Grupos (posixGroup)**
   - Grupos com GID (Group ID) únicos
   - Grupos aninhados (grupos dentro de grupos)
   - Atributos customizados por grupo

2. **Atributos de Usuário POSIX**
   - UID, GID, shell de login, home directory
   - Memberof (associação do usuário a grupos)
   - Sudoers rules (definição de privilégios sudo)

3. **Controle de Acesso a Nível LDAP (HBAC)**
   - **Host-Based Access Control (HBAC):** Define quais usuários podem acessar quais máquinas
   - Filtros baseados em grupos, usuários, serviços e hosts
   - Políticas de tempo e restrições adicionais

#### 2.1.2 Resposta: SIM, LDAP Suporta RBAC

A resposta é **SIM**, o LDAP do FreeIPA suporta RBAC de forma adequada para sistemas Linux por meio de:

- **Groups:** Usuários são organizados em grupos com permissões associadas
- **HBAC Policies:** Restringem acesso a hosts específicos baseado em grupos
- **Sudoers Rules:** Definem privilégios de escalação com base em grupos
- **File Permissions:** ACLs no filesystem respeitam a estrutura de grupos

#### 2.1.3 Fluxo de Funcionamento sem Kerberos

```
┌─────────────┐
│   Usuário   │
└──────┬──────┘
       │ ssh usuario@servidor.cloudlabs.ufscar
       ▼
┌──────────────────┐
│  SSHD + PAM      │ ◄─── PAM verifica credenciais via LDAP
└──────┬───────────┘
       │
       ▼
┌──────────────────────────────┐
│  SSSD                        │ ◄─── Query ao LDAP
├──────────────────────────────┤
│ - Valida usuário/senha       │
│ - Busca UID, GID, grupos     │
│ - Verifica HBAC policies     │
│ - Cria home directory        │
└──────┬───────────────────────┘
       │
       ▼
┌────────────────────┐
│   FreeIPA LDAP     │
├────────────────────┤
│ Usuários           │
│ Grupos (RBAC)      │
│ HBAC Policies      │
│ Sudoers Rules      │
└────────────────────┘
```

**Vantagens desta abordagem:**
- Elimina a complexidade do Kerberos (sincronização temporal, tickets, KDC failover)
- Mantém autenticação centralizada via LDAP
- RBAC totalmente suportado via grupos e policies
- Reduz número de componentes críticos
- Simplifica troubleshooting

**Limitações a considerar:**
- Sem SSO a nível de sistema operacional (não há tickets compartilhados entre máquinas)
- Cada login requer validação com LDAP (latência de rede)
- Requer conectividade constante com servidor LDAP para PAM
- Cache local necessário em caso de desconexão LDAP (SSSD cache)

### 2.2 Quando Kerberos Seria Realmente Necessário

O Kerberos é particularmente valioso em cenários como:

1. **SSO entre múltiplos serviços no mesmo host** - onde você copia um ticket entre serviços sem reenviar credenciais
2. **Ambientes com muitas máquinas distribuídas geograficamente** - onde seria ruim estar constantemente consultando LDAP
3. **Integração com aplicações legadas** que exigem tickets Kerberos (e.g., autenticação Windows, alguns apps bancárias)
4. **Ambientes com requisitos de auditoria granular** de tipo "qual serviço foi chamado com qual credencial"

Para a infraestrutura do CloudLabs, **nenhum desses cenários é crítico**, portanto **proceder sem Kerberos é viável**.

---

## 3. Introdução ao OpenFGA para Autorização Web

### 3.1 O Problema: Autorização Monolítica no Keycloak

A arquitetura anterior propunha usar **apenas Keycloak + LDAP** para sistemas web. Embora isso funcione para **autenticação**, criar modelos de **autorização granular** apenas com Keycloak introduz problemas:

1. **Escalabilidade de Regras:** Adicionar novas permissões requer mudanças em muitos lugares
2. **Complexity in Application Code:** Lógica de autorização fica espalhada entre Keycloak e aplicações
3. **Reutilização Limitada:** Cada aplicação reimplementa suas próprias regras
4. **Auditoria Difícil:** Não há um ponto único para verificar "por que o usuário pode ou não fazer algo"

### 3.2 Por Que OpenFGA?

**OpenFGA** (Fine-Grained Authorization) é uma solução de código aberto derivada do "Zanzibar" do Google, que implementa um modelo relacional de autorização.

#### 3.2.1 Capacidades do OpenFGA

```
Modelo Relacional: Definir quem pode fazer o quê em qual recurso

Exemplo (pseudo-código):
user:alice can edit resource:document-1
user:alice can view resource:project-2
group:admins can delete resource:user-*
user:bob can comment resource:document-1 (via group:editors membership)
```

#### 3.2.2 Vantagens

1. **Separação de Responsabilidades**
   - Autenticação: Keycloak (quem é o usuário?)
   - Autorização: OpenFGA (o que pode fazer?)

2. **Expressividade**
   - Relações complexas: "usuários em admin_team de um projeto podem gerenciar esse projeto"
   - Hierarquias: "admins podem fazer tudo que editores podem fazer"
   - Dynamic memberships: "proprietário de um recurso pode compartilhá-lo"

3. **Performance**
   - Check autorização: ~1ms por query
   - Ideal para decisões em tempo real em aplicações web

4. **Reutilização**
   - Uma única instância OpenFGA para toda infraestrutura web
   - Múltiplas aplicações consultam o mesmo modelo
   - Mudanças de política em um lugar

5. **Auditoria**
   - Histórico completo de relacionamentos
   - Rastreabilidade de decisões de acesso

### 3.3 Fluxo de Autenticação + Autorização Web com OpenFGA

```
┌──────────────┐
│   Usuário    │
└──────┬───────┘
       │ 1. Login via Browser
       ▼
┌────────────────────┐
│    Keycloak        │ ◄─── Autentica contra LDAP
├────────────────────┤
│ - Valida credencial│
│ - Gera JWT Token   │
└────────┬───────────┘
         │ 2. Retorna token + username
         ▼
┌────────────────────────┐
│   Aplicação Web        │
│   (ex: Incus API)      │ ◄─── Request com JWT Token
└────────┬───────────────┘
         │ 3. Valida token JWT com Keycloak
         │ 4. Extrai username do token
         │
         ▼
┌──────────────────────────┐
│   OpenFGA Check          │
├──────────────────────────┤
│ user:alice pode          │
│ criar containers em      │
│ projeto:production?      │
└────────┬─────────────────┘
         │ Query: user "alice" can "create" container in project "production"
         ▼
┌────────────────────────┐
│   OpenFGA              │
│   Authorization Store  │
└────────┬───────────────┘
         │ 5. Resposta: Autorizado/Não Autorizado
         ▼
┌────────────────────────┐
│ Aplicação processa     │
│ request ou nega acesso │
└────────────────────────┘
```

### 3.4 Exemplos de Casos de Uso em CloudLabs

**Incus (Container/VM Management):**
```
Modelo: 
- user:alice pode criar containers em project:team-data
- user:alice pode deletar containers que ela criou
- group:admins pode deletar qualquer container
- user:bob pode ler recursos de project:team-data (viewer role)
```

**OpenStack:**
```
Modelo:
- user:alice é proprietária do projeto:project-1
- proprietária pode adicionar membros e deletar instâncias
- user:charlie é membro do projeto:project-1 com role:viewer
- viewers podem ver instâncias mas não criar/deletar
```

**Grafana:**
```
Modelo:
- user:alice pode editar dashboards no folder:team-monitoring
- group:data_engineers podem criar novas queries no datasource:prometheus
- user:bob é viewer de todos os dashboards
```

---

## 4. Arquitetura Revisada (Sem Kerberos + Com OpenFGA)

### 4.1 Componentes Principais

```
┌─────────────────────────────────────────────────────────────────┐
│                    INFRAESTRUTURA CLOUDLABS                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           CAMADA DE REDE E INFRAESTRUTURA                │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │  • VPN Gateway                                            │   │
│  │  • DNS Server (cloudlabs.ufscar)                          │   │
│  │  • Certificate Authority (CA)                            │   │
│  │    - Emite certificados para LDAP (ldaps://)             │   │
│  │    - Emite certificados para HTTPS                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        CAMADA DE GERENCIAMENTO DE IDENTIDADE             │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │  FreeIPA                                     │   │
│  │  ├─ LDAP Server                                          │   │
│  │  │  ├─ Usuários (uid, gid, ssh keys)                    │   │
│  │  │  ├─ Grupos (RBAC para Linux)                         │   │
│  │  │  └─ HBAC Policies (Host-Based Access Control)        │   │
│  │  ├─ Sudoers Rules (Escalação de privilégios)            │   │
│  │  └─ Host Management (registro de máquinas)              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │    CAMADA WEB: AUTENTICAÇÃO + AUTORIZAÇÃO                │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │                                                            │   │
│  │  Keycloak (Docker/Kubernetes)                            │   │
│  │  └─ Valida credenciais contra LDAP FreeIPA             │   │
│  │  └─ Emite JWT tokens (OpenID Connect)                   │   │
│  │  └─ Integra MFA (TOTP, U2F)                             │   │
│  │                                                            │   │
│  │  OpenFGA (Docker/Kubernetes)                            │   │
│  │  └─ Store relacional de autorização                     │   │
│  │  └─ Valida permissões granulares                        │   │
│  │  └─ Suporta hierarquias e relações dinâmicas            │   │
│  │                                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         CAMADA LINUX: AUTENTICAÇÃO POSIX                 │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │  Cada Host Linux                                          │   │
│  │  ├─ SSHD (SSH Daemon)                                    │   │
│  │  ├─ PAM (Pluggable Authentication Modules)              │   │
│  │  ├─ SSSD (System Security Services Daemon)              │   │
│  │  │  └─ Conecta a FreeIPA para auth/groups               │   │
│  │  │  └─ Cria home directories dinamicamente              │   │
│  │  │  └─ Resolve UID/GID/grupos                           │   │
│  │  └─ ACL + Sudoers (via LDAP)                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           APLICAÇÕES WEB INTEGRADAS                       │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │  • OpenStack (Keycloak OIDC + OpenFGA)                  │   │
│  │  • Incus (Keycloak OIDC + OpenFGA)                      │   │
│  │  • Grafana (Keycloak OAuth + OpenFGA)                   │   │
│  │  • Kubernetes Dashboard (Keycloak OIDC + OpenFGA)       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1.1 Arquitetura de Infraestrutura na Magalu Cloud

Nesta revisão, a infraestrutura de identidade e autorização é montada em três VMs dentro da Magalu Cloud:

- **VM 1 – VPN Gateway (Wireguard)**
  - conecta a rede Magalu Cloud ao servidor Nimbus
  - garante disponibilidade de acesso ao cluster Incus privado
  - expõe rotas apenas para as VMs de Keycloak/OpenFGA e para o cluster

- **VM 2 – Auth/Authz (Keycloak + OpenFGA)**
  - roda Keycloak para autenticação OIDC
  - roda OpenFGA para autorização de recursos
  - consome o FreeIPA LDAP para validar credenciais
  - atende o Incus Web UI e APIs

- **VM 3 – FreeIPA / LDAP**
  - armazena usuários, grupos POSIX, HBAC e sudoers
  - serve como backend de autenticação POSIX para hosts Linux
  - não é usado como KDC Kerberos, apenas como LDAP

```text
[ Nimbus local ] -- Wireguard --> [ VM 1 VPN Gateway ]
                                    |
                                    +--> [ VM 2 Keycloak + OpenFGA ]
                                    |
                                    +--> [ VM 3 FreeIPA / LDAP ]
```

Essa topologia garante:
- disponibilidade de autenticação e autorização para o cluster Incus
- separação clara de funções entre VPN, identidade e autorização
- baixo acoplamento entre o LDAP POSIX e o backend web

### 4.1.2 Fluxos de rede

- O **Nimbus** se conecta à **VM 1** via Wireguard.
- A **VM 1** encaminha tráfego seguro para as VMs de Keycloak/OpenFGA e FreeIPA.
- O **Incus** acessa a **VM 2** internamente ou através do gateway, conforme a topologia de rede.
- O **Keycloak** consulta a **VM 3** para validar credenciais LDAP.
- O **OpenFGA** pode ser consultado diretamente pelo Incus ou por um service layer entre aplicação e autorização.

### 4.2 Fluxo de Acesso POSIX (Linux)

```
1. Usuário tenta fazer SSH
   $ ssh usuario@servidor.cloudlabs.ufscar

2. SSHD intercepta credenciais

3. PAM + SSSD consultam FreeIPA LDAP:
   - Valida username/password
   - Busca atributos POSIX (UID, GID, shell)
   - Verifica grupos do usuário
   - Valida HBAC Policy (pode acessar este host?)

4. Se autorizado:
   - SSSD cria home directory em /home/usuario
   - Shell é iniciado com contexto do usuário

5. Se usuário tenta sudo:
   - PAM valida contra Sudoers Rules no LDAP
   - Verifica grupo do usuário (ex: group:admins)
```

### 4.3 Fluxo de Acesso Web

```
1. Usuário acessa aplicação web (ex: Incus API)

2. Aplicação redireciona para Keycloak
   - Keycloak OIDC Flow inicia

3. Usuário faz login em Keycloak
   - Keycloak valida contra FreeIPA LDAP
   - MFA pode ser exigida

4. Keycloak retorna JWT token com:
   - sub (subject = user ID)
   - username
   - groups (opcionalmente)
   - roles (Keycloak-specific)

5. Aplicação faz request com JWT token para seu backend

6. Backend extrai username do token

7. Backend consulta OpenFGA:
   Query: "user:alice pode 'criar containers' em 'projeto:production'?"

8. OpenFGA responde com Allow/Deny baseado em store relacional

9. Aplicação processa request ou retorna 403 Forbidden
```
