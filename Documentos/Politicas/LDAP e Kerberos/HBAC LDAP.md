## 1. Introdução e Escopo

Este documento define as políticas de **Host-Based Access Control (HBAC)** e **Sudoers (RBAC)** dentro da infraestrutura. O objetivo é estabelecer um mapeamento seguro e granular entre grupos de utilizadores e grupos de hosts, garantindo que o acesso seja restrito apenas ao pessoal necessário.

Nesta fase da infraestrutura, adotamos as seguintes políticas:

- **Acesso (HBAC):** Define quem pode realizar login via SSH, SFTP ou SCP.
    
- **Privilégio (SUDO):** Define quem possui poderes de superutilizador (_root_).
    
- **Diretriz:** Por simplificação, todo o utilizador autorizado a acessar uma máquina terá privilégios de `sudo`.

---
## Fundamentação Teórica

Para a definição real das políticas de HBAC, é necessário um entendimento sobre as querys de busca das relações entre usuários e hosts. Assim, podemos entender como fazer uma política simples e com boa performance, pois é crítico que as buscas das relações sejam rápidas.

O acesso em nossa arquitetura tem o seguinte fluxo:

`usuário loga visa ssh` -> `sssd na máquina` -> `ldap` -> `sssd autoriza ou não`

O processo de autenticação e autorização em ambientes geridos pelo FreeIPA, operando em conjunto com o _System Security Services Daemon_ (SSSD), é estruturado para garantir alta performance e minimizar a latência durante o login. A avaliação das políticas de _Host-Based Access Control_ (HBAC) não ocorre por meio de uma varredura sequencial ou leitura completa de todas as regras existentes no diretório.

A execução da avaliação de acesso divide-se em etapas entre o cliente (SSSD) e o servidor (LDAP). Na primeira etapa, o SSSD realiza uma consulta indexada ao servidor solicitando exclusivamente as regras HBAC aplicáveis à máquina de origem. A requisição filtra as regras buscando aquelas que referenciam o host atual de forma direta ou por meio dos grupos de hosts aos quais a máquina pertence. Esta operação reduz drasticamente a transferência de dados e o tempo de resposta, pois o servidor LDAP processa a requisição e retorna ao SSSD apenas um subconjunto estrito de regras, ignorando todo o restante do banco de dados.

Com as regras de host armazenadas na memória local do cliente, a segunda etapa consiste em validar a autorização do usuário em relação a esse subconjunto. A alta performance nesta fase é assegurada pelo plugin `memberOf` ativo no servidor LDAP. Historicamente, descobrir a associação de um usuário a múltiplos grupos aninhados exigiria buscas recursivas custosas. O plugin `memberOf` mitiga este problema calculando as associações em segundo plano no próprio servidor. Ele injeta e mantém um atributo diretamente no objeto do usuário contendo a lista consolidada de todos os grupos dos quais ele faz parte. Dessa forma, o SSSD baixa o objeto do usuário com esta lista já pronta e executa uma validação local, realizando a interseção entre os grupos listados no atributo `memberOf` do usuário e os grupos exigidos nas regras da máquina. A avaliação ocorre inteiramente na memória RAM do host e a autorização é concedida de forma imediata assim que a primeira correspondência verdadeira é identificada.

Conclui-se que o número total de regras possui impacto mínimo na performance geral do ecossistema, contanto que o modelo de gestão baseado em grupos seja estritamente adotado. O ambiente é capaz de processar milhares de políticas eficientemente se os acessos forem concedidos através do cruzamento de Grupos de Usuários e Grupos de Hosts. A degradação de desempenho e a lentidão no processo de login manifestam-se apenas quando as regras são configuradas com mapeamentos granulares de indivíduos para máquinas específicas. Essa prática eleva o tamanho dos objetos LDAP transferidos na rede e exige processamento adicional de CPU do SSSD para processar listas extensas. Portanto, a escalabilidade e a agilidade na resposta não dependem de um limite baixo de regras, mas da aplicação correta de um design de agrupamento estruturado.

---
## 3. Matriz de Acesso e HBAC

A autorização é estruturada por níveis, respeitando a hierarquia definida nos documentos anteriores.

### 3.1. Regras de Escopo Global e Core

| Nome da Regra             | Host Group (Alvo)    | User Groups (Autorizados)             |
| ------------------------- | -------------------- | ------------------------------------- |
| **HBAC_Global_Admin**     | `cloudlabs-hosts`    | `admin`, `infra`                      |
| **HBAC_IAM_Core**         | `iam-cluster`        | `iam-admin`, `monitoring-admin`       |
| **HBAC_Monitoring**       | `monitoring-cluster` | `monitoring-admin`                    |
| **HBAC_Incus_Global**     | `incus-cluster`      | `incus-admin`, `monitoring-admin`     |
| **HBAC_OpenStack_Global** | `openstack-cluster`  | `openstack-admin`, `monitoring-admin` |

### 3.2. Regras Granulares (Instâncias)

| Nome da Regra      | Host Group (Alvo) | User Groups (Autorizados) |
| ---------------------- | --------------------- | ----------------------------- |
| **HBAC_Incus_Stratus** | `incus-stratus`       | `incus-stratus-admin`         |
| **HBAC_Incus_Cirrus**  | `incus-cirrus`        | `incus-cirrus-admin`          |

> **Nota:** Administradores globais (ex: `incus-admin`) não precisam ser listados em regras granulares (ex: `incus-stratus`), pois já possuem acesso via regra de nível superior.

---
## 4. Políticas de Governança de Acesso

### 4.1. Exceção de Gateways

Os grupos de **Gateways** e **VPNs** não possuem tabelas HBAC dedicadas nesta fase. O acesso é restrito ao grupo `infra` (via regra global `cloudlabs-hosts`), garantindo que a borda da rede seja gerida apenas pelos administradores de infraestrutura base. Porém, nada impede no futuro terem regras próprias com a adição de novos grupos de usuários mais granulares.

### 4.2. Simplificação de SUDO

Para cada regra de HBAC de acesso criada, deve existir uma regra de SUDO correspondente que conceda `ALL=(ALL) ALL` para os mesmos grupos de utilizadores. RBACs mais granulares (limitação de comandos específicos) são desencorajados, exceto em casos de extrema necessidade de auditoria, para evitar complexidade desnecessária.

### 4.3. Criação de Novas Regras

A criação de novas tabelas HBAC deve seguir os critérios:

1. **Prioridade para Grupos:** Nunca criar regras para utilizadores isolados.
    
2. **Não-Redundância:** Antes de criar uma regra, verificar se o utilizador já não herda o acesso via um grupo de hierarquia superior.
    
3. **Segregação por Função:** Se um novo cluster for criado (ex: `kubernetes-cluster`), uma nova tabela HBAC deve ser instanciada imediatamente.