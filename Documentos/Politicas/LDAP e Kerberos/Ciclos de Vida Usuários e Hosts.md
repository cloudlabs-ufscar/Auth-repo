## 1. Diretório como Fonte Única de Verdade (SSoT)

O diretório LDAP do FreeIPA é a autoridade central para todos os atributos de identidade.

- **Exclusividade:** Nenhuma entidade deve ser criada localmente em servidores, exceto as contas de contingência já definidas (`root`, `ubuntu`).
    
- **Sincronização:** Alterações em permissões ou chaves devem ser realizadas exclusivamente via CLI ou UI do FreeIPA, nunca via edição manual de arquivos locais nos hosts.

## 2. Ciclo de Vida de Utilizadores

### 2.1. Padronização e Nomenclatura

- **Case Sensitivity:** Todos os nomes de utilizador (_usernames_) devem ser rigorosamente escritos em **letras minúsculas**.
    
- **Atributos POSIX:** Toda conta deve possuir atributos POSIX válidos. O shell padrão para todos os utilizadores é, obrigatoriamente, `/bin/bash`.

### 2.2. Provisionamento de Utilizadores Internos

Membros do CloudLabs seguem o fluxo de "Acesso por Padrão" dentro do grupo de pesquisa:

1. **Associação de Grupos:** Inclusão obrigatória no grupo raiz `cloudlabs` e no subgrupo funcional (ex: `iam-admin`, `monitoring-admin`).
    
2. **Docentes:** Professores e coordenadores devem ser adicionalmente associados ao grupo `admin`.
    
3. **Credenciais:** Cadastro de chave pública SSH diretamente no diretório e definição de senha temporária para troca no primeiro login (Kerberos).
    
4. **Privilégios:** Por definição política, membros do grupo `cloudlabs` recebem privilégios administrativos via sudoers nas máquinas autorizadas por HBAC.

### 2.3. Provisionamento de Utilizadores Externos

Investigadores convidados ou parceiros seguem o fluxo de "Acesso Restrito":

1. **Isolamento:** Associação obrigatória ao grupo `externo`.
    
2. **Autorização:** O acesso é bloqueado por padrão e concedido apenas a hosts específicos via regras de HBAC pontuais.
    
3. **Temporalidade:** Contas externas devem possuir uma data de expiração definida no diretório no momento da criação.

### 2.4. Manutenção e Deprovisionamento

- **Atualização de Chaves:** Utilizadores são responsáveis por atualizar suas chaves SSH no diretório via _self-service_ ou solicitação ao `iam-admin`.
    
- **Suspensão:** Ao final do vínculo com o grupo, a conta deve ser primeiramente **desativada** (preservando o UID para auditoria de logs) antes de qualquer exclusão definitiva.

---

## 3. Ciclo de Vida de Hosts

### 3.1. Identificação e Agrupamento

Todo host admitido na infraestrutura deve seguir a taxonomia de grupos funcionais. A nomenclatura de grupos de hosts deve ser escrita em minúsculas e utilizar obrigatoriamente o sufixo **`-hosts`**.

**Grupos de Hosts Autorizados:**

- `cloudlabs-hosts` (Raiz obrigatória para todos)
    
- `monitoring-hosts`
    
- `incus-hosts`
    
- `openstack-hosts`
    
- `gateway-hosts`

### 3.2. Admissão e Autenticação

1. **Registro:** O host deve ser registrado no FreeIPA, gerando um _Principal_ Kerberos próprio (`host/fqdn@REALM`).
    
2. **Provisionamento de Chaves:** Uma **keytab** local deve ser gerada e armazenada de forma segura no host (`/etc/krb5.keytab`). Esta chave permite que o servidor se autentique no diretório de forma autônoma para resolver nomes e validar utilizadores.
    
3. **Associação:** O host deve ser imediatamente inserido em seu respectivo grupo funcional para herdar as políticas de HBAC e SUDO.

### 3.3. Retirada de Serviço (Decommissioning)

Quando um host é desligado permanentemente:

1. O registro de host deve ser removido do FreeIPA (`ipa host-del`).
    
2. O _Principal_ Kerberos e todos os certificados associados àquela identidade devem ser revogados automaticamente pelo sistema.
    
3. Os registros DNS (direto e inverso) devem ser limpos para evitar colisões futuras.

---

## 4. Gestão de Grupos de Identidade

Grupos são as unidades fundamentais de autorização.

- **Hierarquia Funcional:** Novos grupos podem ser criados conforme a necessidade de novos serviços, desde que respeitem a nomenclatura funcional (ex: `kubernetes-hosts`).
    
- **Auditoria de Membros:** Trimestralmente, os administradores do grupo `iam-admin` devem revisar a lista de membros dos grupos `-admin` para garantir que o Princípio do Menor Privilégio esteja sendo cumprido.