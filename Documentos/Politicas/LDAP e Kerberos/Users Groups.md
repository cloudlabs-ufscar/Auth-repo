# 1. Introdução

Este documento define a arquitetura lógica dos grupos de utilizadores no serviço de diretório (LDAP). A estrutura aqui detalhada visa garantir um controlo de acesso granular, seguro e escalável para toda a infraestrutura do grupo de investigação, abrangendo desde servidores _bare metal_ até serviços aplicacionais via SSO.

##### 1.1. O Equilíbrio entre Hierarquia e Simplicidade

O modelo de gestão do grupo é inerentemente hierárquico, onde a senioridade e a especialização técnica ditam os níveis de influência. No entanto, níveis excessivos de hierarquia no LDAP geram complexidade operacional e dificultam auditorias.

 **Decisão:** Adotamos o modelo de hierarquia, porém tentando simplificar o máximo possível. Onde a estrutura é profunda o suficiente para garantir o princípio do menor privilégio, mas plana o suficiente para que qualquer administrador consiga visualizar e modificar a árvore sem riscos de efeitos colaterais imprevistos   

##### 1.2. Diferenciação de Escopo: Cloudlabs vs. Externos

Como o LDAP é a nossa "fonte da verdade", ele deve estar preparado para o crescimento. Prevemos o uso do cluster por pesquisadores externos no futuro.

**Decisão:** Estabelecemos uma separação primária clara. Membros internos (Cloudlabs) possuem uma estrutura de vida longa e organizada por competências; membros externos possuem uma estrutura efémera, criada sob demanda e com data de expiração, garantindo que o núcleo da infraestrutura permaneça isolado.

##### 1.3. Evolução Contínua e Agilidade

Uma infraestrutura de pesquisa é orgânica e deve sempre ser revisada e modificada conforme o avanço do projeto.

**Decisão:** A estrutura deve ser flexível. A facilidade de adicionar ou remover subgrupos é prioritária sobre o rigor excessivo de uma taxonomia imutável. O aprimoramento do modelo é um fluxo contínuo, não um estado estático.

##### 1.4. Federação Futura com Keycloak

No presente momento a estruturação é majoritariamente pensada para acessos em máquinas bare-metal, pois o Free-IPA tem esse objetivo primariamente. Porém, é necessário que a estrutura de usuários seja genérica a ponto de a federação futura com o Keycloak conseguirmos atribuir roles rápidamente apenas por meio dos grupos dos usuários.

---
## 2. Topologia de Grupos Primários

A primeira divisão de alto nível no diretório separa os utilizadores em dois domínios lógicos:

1. **`cloudlabs`**: Agrupa os integrantes fixos do grupo de extensão. É subdividido por áreas funcionais (Incus, OpenStack, IAM, etc.).
    
2. **`externos`**: Agrupa utilizadores de colaborações pontuais.
    
    - _Política:_ As subdivisões para externos são temporárias. Grupos específicos para projetos externos devem ser criados e destruídos junto com o ciclo de vida da colaboração.

---
## 3. Estrutura Funcional (Domínio Cloudlabs)

A árvore abaixo detalha como a especialização técnica é traduzida em grupos. O modelo pressupõe uma **herança lógica**: quem está no topo (ex: `admin`) possui os direitos dos níveis inferiores, facilitando a gestão para os líderes de área.

```
admin (Raiz Administrativa)
│
├── incus-admin (Gestão Global de Virtualização)
│   ├── incus-stratus-admin
│   └── incus-cirrus-admin
│
├── openstack-admin (Gestão de Cloud Privada)
│   ├── openstack-cluster1-admin
│   └── openstack-cluster2-admin
│
├── iam-admin (Gestão de Identidades e Acessos)
│   ├── keycloak-admin
│   └── freeipa-admin
│
├── monitoring-admin (Gestão de Observabilidade)
│   ├── prometheus-admin
│   └── grafana-admin
│
└── infra (Sistemas Base e Gateways)
```

> [!NOTE] Atenção a Herança de Grupos
> Como dito acima, um grupo como o de `admin` terá os privilégios de grupos com hierarquia menor. Porém, não necessariamente precisam herdar os outros grupos. Estar em um grupo de hierarquia maior já diz logicamente que tem tais privilégios.

---
## 4. Políticas de Governança e Nomeclatura

Para manter a consistência do diretório ao longo do tempo, as seguintes normas são estabelecidas:

### 4.1. Convenção de Sufixos (Auto-Documentação)

Todo novo grupo deve indicar sua função no nome:

- **`-admin`**: Possui privilégios totais de escrita, configuração e gestão sobre o recurso.
    
- **`-operator`**: Possui privilégios restritos de uso e operação básica, sem permissões administrativas.
    
    - _Exemplo:_ O `incus-stratus-admin` gere o cluster inteiro; um eventual `incus-stratus-operator` apenas criaria containers dentro de limites pré-estabelecidos.

### 4.2. Provisionamento e Menor Privilégio

- **Grupo Primário:** Todo utilizador deve pertencer obrigatoriamente a `cloudlabs` ou `externos`.
    
- **Atribuição Mínima:** Ao integrar um novo membro ao `cloudlabs`, deve-se atribuir o menor privilégio possível dentro de sua área de atuação. A ascensão a grupos `-admin` deve ser tratada como exceção e baseada em necessidade técnica real.

---
## 5. Definição das Áreas de Atuação

- **`incus-admin`**: Responsável pela camada de containers e VMs via Incus. Subgrupos gerem clusters específicos (Stratus, Cirrus).
    
- **`openstack-admin`**: Responsável pela orquestração complexa de nuvem e recursos de rede associados ao OpenStack.
    
- **`iam-admin`**: Gere FreeIPA, Keycloak e as políticas de autorização no OpenFGA.
    
- **`monitoring-admin`**: Gere a stack de visibilidade (Prometheus, Grafana), garantindo que a infraestrutura seja mensurável.
    
- **`infra`**: Gere o hardware bare metal, sistemas operativos de base, redes físicas e gateways de acesso que suportam todos os outros serviços.