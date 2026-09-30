# Integração Keycloak e OpenFGA

Este documento detalha as decisões de modelagem de identidade, o esquema de grupos planos no Keycloak, as configurações dos clientes OIDC do Incus e a sincronização de eventos com o OpenFGA.

---

## 1. O Modelo dos 18 Grupos Planos (Flat Groups)

### A Matriz de Projetos e Níveis de Privilégio
Para isolar os recursos computacionais dos times, foram estabelecidos **6 projetos** no laboratório, cada um dividido estritamente em **3 níveis de privilégio**:

| Projeto | Grupo Admin | Grupo Operator | Grupo User |
| :--- | :--- | :--- | :--- |
| **IAM** | `iam-project-admin` | `iam-project-operator` | `iam-project-user` |
| **Monitoring** | `monitoring-project-admin` | `monitoring-project-operator` | `monitoring-project-user` |
| **OpenStack** | `openstack-project-admin` | `openstack-project-operator` | `openstack-project-user` |
| **Security** | `security-project-admin` | `security-project-operator` | `security-project-user` |
| **Network** | `network-project-admin` | `network-project-operator` | `network-project-user` |
| **Admin Geral** | `admin-project-admin` | `admin-project-operator` | `admin-project-user` |

* **Admin (`admin`):** Controle total sobre as instâncias, redes, discos, snapshots e configurações do projeto.
* **Operator (`operator`):** Inicialização, reinício, parada e visualização operacional das instâncias.
* **User (`user`):** Acesso de visualização (`can_view`) aos recursos do projeto.

---

### Por que os Grupos DEVEM ser Planos? (Análise Técnica Aprofundada)

Uma das dúvidas mais frequentes na concepção deste modelo foi: *"Faz sentido criar grupos aninhados no Keycloak (ex: `/iam-project/admin` e `/monitoring-project/admin`) ou isso quebra o sistema?"*

A investigação comprovou que **grupos aninhados quebram completamente o sistema** por duas razões técnicas críticas:

#### Motivo 1: Comportamento do Plugin SPI (`EventParser.java`)
O plugin do Keycloak que publica eventos no OpenFGA ([`EventParser.java`](https://github.com/cloudlabs-ufscar/keycloak-openfga-event-publisher)) lê o nome do grupo a partir do JSON de representação do evento administrativo do Keycloak:

```java
// Trecho de EventParser.java
public String getEventObjectName() {
    return getObjectByAttributeName("name");
}

private String getObjectByAttributeName(String attributeName) {
    ObjectMapper mapper = new ObjectMapper();
    JsonNode jsonNode = mapper.readTree(representation);
    return jsonNode.get(attributeName).asText();
}
```

* No Keycloak, se você cria um grupo aninhado com o caminho `/iam-project/admin`, o campo `path` é `"/iam-project/admin"`, mas o campo `name` é simplesmente `"admin"`.
* Se houvesse aninhamento, quando um usuário fosse adicionado a `/iam-project/admin` e outro a `/monitoring-project/admin`, o plugin leria `name: "admin"` para **ambos**.
* O plugin enviaria para o OpenFGA a tupla `user:usuario -> member -> group:admin`.
* **Consequência desastrosa:** O isolamento entre projetos colapsaria. Todos os administradores de qualquer projeto virariam membros do mesmo grupo genérico `group:admin` no OpenFGA!

#### Motivo 2: Esquema do Modelo de Autorização do Incus (`model-incus.fga`)
O modelo do OpenFGA carregado pelo próprio Incus define o tipo `group` da seguinte forma:

```text
type user

type group
  relations
    define member: [user]
```

* O Incus define explicitamente que `member` só pode ser do tipo `[user]`.
* Ele **NÃO** permite `[user, group#member]`.
* Se tentássemos aninhar grupos no OpenFGA, a API do OpenFGA rejeitaria as requisições com erro de validação de esquema (`Type definition does not allow relation group#member`).

**Conclusão:** A convenção plana com hífen (`<projeto>-<nivel>`, como `iam-project-admin`) é a única compatível, segura e à prova de ambiguidades.

---

## 2. Configuração dos Clients Incus no Keycloak

No arquivo [`schema-keycloak.json`](../../scripts/ansible-iam/roles/deploy/files/schema-keycloak.json), foram consolidadas as configurações dos dois clientes OIDC responsáveis pelos clusters em produção: **`incus-cirrus`** e **`incus-stratus`**.

### Remoção do Client Legado `incus`
Existia no repositório um client genérico chamado `incus`, configurado como confidencial (`publicClient: false`) e com políticas estáticas de autorização baseadas em roles locais (`Politica-Acesso-Role-Incus`). Esse client foi inteiramente removido porque:
1. Os clusters de produção reais operam individualmente como `incus-cirrus` e `incus-stratus`.
2. A política estática baseada em roles conflitava com a autorização externa delegada ao OpenFGA.

### Atributos Cruciais dos Clients `incus-cirrus` e `incus-stratus`
```json
{
  "clientId": "incus-cirrus",
  "name": "Client Incus Cirrus",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": true,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "redirectUris": [
    "https://cirrus.dc.ufscar.br:8443/*"
  ],
  "webOrigins": [
    "https://cirrus.dc.ufscar.br:8443"
  ],
  "attributes": {
    "oauth2.device.authorization.grant.enabled": "true"
  }
}
```

* **`publicClient: true`:** Essencial. Tanto a Web UI quanto a CLI do Incus utilizam OAuth2 com **PKCE** (Proof Key for Code Exchange). Clientes públicos não exigem client secret na aplicação final, permitindo que a CLI autentique localmente sem vazar chaves confidenciais.
* **`oauth2.device.authorization.grant.enabled: "true"`:** Habilita o Device Flow (RFC 8628) para permitir autenticação via terminal sem precisar abrir navegadores locais na máquina do cluster.
* **`redirectUris` e `webOrigins`:** Apontam para os domínios reais de produção na porta `8443`, prevenindo erros de CORS na Web GUI.

---

## 3. Segurança e Parametrização do Provedor GitHub

No [`schema-keycloak.json`](../../scripts/ansible-iam/roles/deploy/files/schema-keycloak.json), o Provedor de Identidade (IdP) do GitHub foi sanitizado para que o repositório não contenha nenhuma credencial exposta em texto puro:

```json
"identityProviders": [
  {
    "alias": "github",
    "providerId": "github",
    "enabled": true,
    "updateProfileFirstLoginMode": "on",
    "trustEmail": false,
    "storeToken": false,
    "addReadTokenRoleOnCreate": false,
    "authenticateByDefault": false,
    "linkOnly": false,
    "config": {
      "hideOnLoginPage": "false",
      "acceptsPromptNoneForwardFromClient": "false",
      "clientId": "${env.GITHUB_CLIENT_ID:}",
      "clientSecret": "${env.GITHUB_CLIENT_SECRET:}",
      "disableUserInfo": "true",
      "filteredByClaim": "false",
      "syncMode": "LEGACY",
      "defaultScope": "openid user:email read:org"
    }
  }
]
```

* As expressões `${env.GITHUB_CLIENT_ID:}` e `${env.GITHUB_CLIENT_SECRET:}` instruem o Keycloak a resolver esses valores dinamicamente a partir das variáveis de ambiente injetadas no container pelo Docker Compose.
* O escopo `defaultScope: "openid user:email read:org"` garante que o Keycloak tenha permissão para ler as organizações do usuário no GitHub.

---

## 4. Esquema de Tuplas do OpenFGA (`schema-openfga-1.json`)

O arquivo [`schema-openfga-1.json`](../../scripts/ansible-iam/roles/deploy/files/schema-openfga-1.json) define as relações fixas entre os grupos do Keycloak e os objetos do Incus:

```json
{
  "writes": {
    "tuple_keys": [
      { "user": "group:iam-project-admin#member", "relation": "admin", "object": "project:iam-project" },
      { "user": "group:iam-project-operator#member", "relation": "operator", "object": "project:iam-project" },
      { "user": "group:iam-project-user#member", "relation": "user", "object": "project:iam-project" },

      { "user": "group:monitoring-project-admin#member", "relation": "admin", "object": "project:monitoring-project" },
      { "user": "group:monitoring-project-operator#member", "relation": "operator", "object": "project:monitoring-project" },
      { "user": "group:monitoring-project-user#member", "relation": "user", "object": "project:monitoring-project" },

      { "user": "group:openstack-project-admin#member", "relation": "admin", "object": "project:openstack-project" },
      { "user": "group:openstack-project-operator#member", "relation": "operator", "object": "project:openstack-project" },
      { "user": "group:openstack-project-user#member", "relation": "user", "object": "project:openstack-project" },

      { "user": "group:security-project-admin#member", "relation": "admin", "object": "project:security-project" },
      { "user": "group:security-project-operator#member", "relation": "operator", "object": "project:security-project" },
      { "user": "group:security-project-user#member", "relation": "user", "object": "project:security-project" },

      { "user": "group:network-project-admin#member", "relation": "admin", "object": "project:network-project" },
      { "user": "group:network-project-operator#member", "relation": "operator", "object": "project:network-project" },
      { "user": "group:network-project-user#member", "relation": "user", "object": "project:network-project" },

      { "user": "group:admin-project-admin#member", "relation": "admin", "object": "project:admin-project" },
      { "user": "group:admin-project-operator#member", "relation": "operator", "object": "project:admin-project" },
      { "user": "group:admin-project-user#member", "relation": "user", "object": "project:admin-project" },

      { "user": "group:admin-project-admin#member", "relation": "admin", "object": "server:incus" }
    ]
  }
}
```

### A Tupla de Super-Administração do Servidor
A adição da última tupla:
```json
{ "user": "group:admin-project-admin#member", "relation": "admin", "object": "server:incus" }
```
Garante que os administradores da infraestrutura central (`admin-project-admin`, como `henrique`, `zematheus`, `helio`, `matias`) tenham privilégios de **administração global de todo o cluster Incus** (criação de projetos, storage pools, perfis e configurações de rede de baixo nível), além do acesso ao seu próprio projeto de instâncias.
