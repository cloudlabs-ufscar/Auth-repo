# 🔌 Plugin SPI: `keycloak-openfga-event-publisher`

Este documento detalha a arquitetura, funcionamento interno, eventos monitorados, configuração e código da extensão SPI (Service Provider Interface) **`keycloak-openfga-event-publisher`**, responsável pela sincronização em tempo real entre o **Keycloak 25** e o motor de autorização **OpenFGA**.

---

## 1. O Problema e a Solução Arquitetural

### O Problema da Dessincronização de Identidades
Em arquiteturas modernas de controle de acesso baseado em relacionamentos (**ReBAC / Zanzibar**), o motor de autorização (OpenFGA) precisa saber a quais grupos cada usuário pertence para avaliar permissões em projetos e servidores. Sem automação:
* Os administradores teriam que cadastrar o usuário no Keycloak e, manualmente, executar comandos de tuplas (`fga tuple write`) no OpenFGA.
* Remoções de usuários ou trocas de equipe no Keycloak deixariam "tuplas órfãs" no OpenFGA, criando graves falhas de segurança (*privilege creep*).

### A Solução: Event-Driven Sincronização via SPI
O plugin atua como um **listener de eventos interno no Keycloak**. Sempre que uma alteração de grupo ou associação de usuário ocorre no Keycloak (seja via Console Web, REST API ou fluxo de Onboarding automatizado), o plugin intercepta o evento no mesmo ciclo de vida e reflete a alteração no OpenFGA em milissegundos:

```mermaid
flowchart TD
    subgraph KEYCLOAK["Keycloak 25 (cumulus.dc.ufscar.br:8443)"]
        ADMIN["Administrador / Onboarding GitHub"] -->|Adiciona membro ao grupo| REALM["Realm 'cloudlabs'"]
        REALM -->|Dispara Evento Interno:<br/>AdminEvent / GROUP_MEMBERSHIP| SPI["SPI: openfga-events-publisher"]
    end

    subgraph PLUGIN_INTERNALS["Estrutura Interna do Plugin (Java 17)"]
        SPI --> PARSER["EventParser:<br/>Filtra ResourceType.GROUP<br/>Extrai userId e groupName"]
        PARSER --> HANDLER["OpenFgaClientHandler:<br/>Monta ClientWriteRequest"]
    end

    subgraph OPENFGA_STACK["OpenFGA Engine (:8080)"]
        HANDLER -->|HTTP POST /stores/{id}/write<br/>(openfga-sdk:0.5.0)| FGA_API["API OpenFGA :8080"]
        FGA_API -->|Persiste Tupla ReBAC| PG_FGA[("PostgreSQL OpenFGA<br/>Tabela: tuple_key")]
    end
```

---

## 2. Anatomia Técnica da Extensão

* **Arquivo JAR no repositório:** [`scripts/ansible-iam/roles/deploy/files/keycloak-openfga-event-publisher.jar`](../../scripts/ansible-iam/roles/deploy/files/keycloak-openfga-event-publisher.jar)
* **Localização no container Docker:** `/opt/keycloak/providers/keycloak-openfga-event-publisher.jar`
* **Versão:** `1.0.1` (Java 17, compatível com Keycloak 25 Quarkus)
* **Dependência Central:** `dev.openfga:openfga-sdk:0.5.0`
* **Ponto de Registro SPI:** `META-INF/services/org.keycloak.events.EventListenerProviderFactory` contendo:
  ```text
  com.twogenidentity.keycloak.OpenFgaEventListenerProviderFactory
  ```

### Principais Classes e Responsabilidades:

| Classe | Pacote | Responsabilidade |
| :--- | :--- | :--- |
| **`OpenFgaEventListenerProviderFactory`** | `com.twogenidentity.keycloak` | Registra o identificador do listener (`openfga-events-publisher`) no motor Quarkus do Keycloak e instancia o provider com as variáveis de ambiente. |
| **`OpenFgaEventListenerProvider`** | `com.twogenidentity.keycloak` | Implementa a interface `org.keycloak.events.EventListenerProvider`. Recebe os métodos `onEvent(Event)` e `onEvent(AdminEvent, boolean)`. |
| **`EventParser`** | `com.twogenidentity.keycloak.event` | Inspeciona `ResourceType`, `OperationType` e limpa o path do grupo (converte `/iam-project-admin` para `iam-project-admin`). |
| **`OpenFgaClientHandler`** | `com.twogenidentity.keycloak.service` | Mantém a conexão com a API do OpenFGA via `OpenFgaClient` e converte o evento em `writes` ou `deletes` de tuplas. |
| **`OpenFgaHelper`** | `com.twogenidentity.keycloak.utils` | Utilitários de mapeamento e resolução de identificadores. |

---

## 3. Eventos Monitorados e Tradução de Tuplas

O plugin escuta principalmente eventos administrativos (`AdminEvent`):

### 1. Inclusão de Usuário em Grupo (`GROUP_MEMBERSHIP_CREATE`)
* **Trigger no Keycloak:** Um operador adiciona o usuário `nicolas` ao grupo `/iam-project-admin`.
* **Ação do Plugin:**
  Envia requisição `POST /stores/{store_id}/write` com:
  ```json
  {
    "writes": {
      "tuple_keys": [
        {
          "user": "user:nicolas",
          "relation": "member",
          "object": "group:iam-project-admin"
        }
      ]
    }
  }
  ```
* **Efeito no Incus:** O OpenFGA atualiza o grafo. Como `group:iam-project-admin#member` tem relação `admin` no objeto `project:iam-project`, o usuário `nicolas` passa a ter acesso de administrador às VMs do projeto instantaneamente.

### 2. Remoção de Usuário de Grupo (`GROUP_MEMBERSHIP_DELETE`)
* **Trigger no Keycloak:** O usuário é removido do grupo.
* **Ação do Plugin:**
  Envia requisição `POST /stores/{store_id}/write` com a seção `deletes`:
  ```json
  {
    "deletes": {
      "tuple_keys": [
        {
          "user": "user:nicolas",
          "relation": "member",
          "object": "group:iam-project-admin"
        }
      ]
    }
  }
  ```
* **Efeito no Incus:** A tupla é expurgada do PostgreSQL do OpenFGA. Na próxima chamada de API, a resposta é `{"allowed": false}` e o usuário recebe `403 Forbidden`.

---

## 4. Configuração no Repositório

### 4.1 Habilitação no Realm Keycloak (`schema-keycloak.json`)
No arquivo [`schema-keycloak.json`](../../scripts/ansible-iam/roles/deploy/files/schema-keycloak.json), o listener é explicitamente declarado na lista de `eventsListeners`:

```json
{
  "realm": "cloudlabs",
  "enabled": true,
  "eventsListeners": [
    "openfga-events-publisher",
    "jboss-logging"
  ],
  ...
}
```

### 4.2 Injeção de Variáveis no Docker Compose (`docker-compose.yml.j2`)
No arquivo de template [`docker-compose.yml.j2`](../../scripts/ansible-iam/roles/deploy/templates/docker-compose.yml.j2), as configurações de rede interna são injetadas no container do Keycloak:

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:25.0.1
  environment:
    # URL da API interna do OpenFGA na rede Docker Compose
    KC_SPI_EVENTS_LISTENER_OPENFGA_EVENTS_PUBLISHER_API_URL: http://openfga:8080
    
    # Nível de log detalhado para depuração do plugin
    KC_LOG_LEVEL: INFO,com.twogenidentity.keycloak:debug,br.ufscar.dc.cloudlabs:debug
  volumes:
    # Montagem do JAR do plugin na pasta de extensões do Keycloak
    - ./keycloak-openfga-event-publisher.jar:/opt/keycloak/providers/keycloak-openfga-event-publisher.jar
```

---

## 5. Resolução Dinâmica de Store do OpenFGA

O plugin possui capacidade de **auto-descoberta**:
1. Se a variável `OPENFGA_STORE_ID` for configurada, o plugin a utiliza diretamente.
2. Se não for especificada, o `OpenFgaClientHandler` executa `fgaClient.listStores()` no startup:
   * Localiza o Store ativo configurado no OpenFGA (`01KY7TAWJYJ5KR48TK19E1CT99`).
   * Lê o modelo de autorização mais recente via `readAuthorizationModels()`.
   * Vincula as operações de escrita diretamente a esse Store sem necessidade de reiniciar o Keycloak quando o Store é recriado.

---

## 6. Diagnóstico e Verificação de Logs

Para verificar se o plugin está carregado e publicando eventos corretamente no servidor `idp.maas`:

### 1. Confirmar Carregamento do Provider no Boot do Keycloak:
```bash
docker logs keycloak | grep -i "openfga-events-publisher"
```
*Saída esperada:*
```text
2026-09-30 00:00:00,123 INFO [org.keycloak.services] (build-11) KC-SERVICES0001: Loading provider openfga-events-publisher
```

### 2. Acompanhar a Sincronização em Tempo Real:
```bash
docker logs -f keycloak | grep -i "com.twogenidentity.keycloak"
```
*Saída ao adicionar usuário no grupo:*
```text
DEBUG [com.twogenidentity.keycloak.event.EventParser] Parsing event: GROUP_MEMBERSHIP_CREATE on group /iam-project-admin for user nicolas
DEBUG [com.twogenidentity.keycloak.service.OpenFgaClientHandler] Writing tuple: user:nicolas#member -> group:iam-project-admin to OpenFGA store 01KY7TAWJYJ5KR48TK19E1CT99
INFO  [com.twogenidentity.keycloak.service.OpenFgaClientHandler] Successfully synchronized tuple with OpenFGA (HTTP 200)
```
