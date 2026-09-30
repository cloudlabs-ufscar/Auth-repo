# Troubleshooting e Análise de Falhas Resolvidas (Postmortems)

Este documento registra as investigações técnicas aprofundadas, os diagnósticos e as soluções definitivas para os quatro principais problemas enfrentados durante a auditoria e automação da infraestrutura.

---

## Postmortem 1: O Loop de Reinício do Container `migrate` e Timeout no Deploy

### Sintomas
Durante o disparo do workflow no GitHub Actions, todas as tarefas de instalação de pacotes, certificados e cópia de arquivos foram concluídas com sucesso. No entanto, o pipeline travava na tarefa:
```text
TASK [deploy : Start or Update Docker Compose Stack] ***************************
2026/09/25 01:23:45 Run Command Timeout
```
Após exatamente 10 minutos de execução, o client SSH encerrava a conexão por timeout (`exit code 1`).

---

### Diagnóstico no Servidor
Ao inspecionar o estado dos containers na máquina IAM (`200.18.99.87`) via `docker ps -a`, observou-se o seguinte:
```text
CONTAINER ID   IMAGE                    COMMAND              STATUS                         NAMES
6e90c9986cfe   haproxy:2.8-alpine       "docker-entrypoint…" Created                        haproxy
23231c4bb4ed   quay.io/keycloak:25.0.1   "/opt/keycloak/bin…" Created                        keycloak
bfc9688e37ef   openfga/openfga:v1.5.5   "/openfga run"       Created                        openfga
ebf76e9f90ec   openfga/openfga:v1.5.5   "/openfga migrate"   Restarting (0) 44 seconds ago  migrate
9e83ddcac136   postgres:14              "docker-entrypoint…" Up 14 minutes (healthy)        postgres-openfga
b90d990dd3e5   postgres:14              "docker-entrypoint…" Up 14 minutes (healthy)        postgres-keycloak
```

* Os bancos de dados estavam `healthy`.
* Os serviços principais (`openfga`, `keycloak`, `haproxy`) estavam parados no estado `Created`.
* O container **`migrate`** exibia o status:
  `Restarting (0) 44 seconds ago`

---

### Causa Raiz
No arquivo de template [`docker-compose.yml.j2`](../../scripts/ansible-iam/roles/deploy/templates/docker-compose.yml.j2), o container `migrate` estava configurado com:
```yaml
migrate:
  image: openfga/openfga:v1.5.5
  restart: unless-stopped      # <-- CAUSA DO PROBLEMA
  container_name: migrate
  command: migrate
  depends_on:
    postgres-openfga:
      condition: service_healthy

openfga:
  ...
  depends_on:
    migrate:
      condition: service_completed_successfully   # <-- O DOCKER COMPOSE AGUARDA O FIM
```

1. O container `migrate` é uma tarefa **one-shot** (ele executa a migração do banco de dados e finaliza com código de saída `0`).
2. Com a diretiva `restart: unless-stopped`, o daemon do Docker detectava que o processo havia finalizado e o reiniciava imediatamente em um loop contínuo (`Restarting (0)`).
3. O serviço downstream `openfga` possui a regra `condition: service_completed_successfully`. O Docker Compose interpreta um container em estado de reinício como **não finalizado**.
4. Como o `migrate` nunca atingia um estado parado e definitivo, o `docker compose up` do módulo Ansible ficava aguardando indefinidamente até estourar o timeout padrão de 10 minutos do Drone SSH.

---

### Solução Aplicada
1. **Remoção da política de reinício:** Removeu-se a linha `restart: unless-stopped` do serviço `migrate` em [`docker-compose.yml.j2`](../../scripts/ansible-iam/roles/deploy/templates/docker-compose.yml.j2). Agora, após a migração, o container permanece no estado `Exited (0)` e o Docker Compose prossegue instantaneamente.
2. **Aumento do timeout preventivo:** Adicionou-se `command_timeout: 20m` no [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) para garantir margem segura durante downloads de imagens volumosas.

---

## Postmortem 2: Erro de Permissão SSH (`root@200.18.99.87: Permission Denied`)

### Sintomas
Na primeira tentativa de execução remota do Ansible, o playbook falhou imediatamente na fase de coleta de fatos:
```text
TASK [Gathering Facts] *********************************************************
[ERROR]: Task failed: Failed to connect to the host via ssh:
root@200.18.99.87: Permission denied (publickey).
fatal: [200.18.99.87]: UNREACHABLE!
```

---

### Diagnóstico e Causa Raiz
1. No arquivo [`ansible.cfg`](../../scripts/ansible-iam/ansible.cfg), o usuário remoto padrão está definido como:
   ```ini
   remote_user = root
   ```
2. Em servidores Ubuntu e imagens de nuvem, o acesso SSH como `root` é desabilitado por padrão se não houver uma chave pública explicitamente cadastrada em `/root/.ssh/authorized_keys`.
3. Além disso, havia a dúvida se o deploy deveria ser executado pelo usuário `ubuntu` com escalação `become: yes` (sudo). Historicamente, rodar pelo `ubuntu` apresentava inconsistências de permissão no socket `/var/run/docker.sock` e escrita em diretórios protegidos como `/opt/iam` e `/etc/ssl/private/haproxy`.

---

### Solução Aplicada
Manteve-se o `remote_user = root` (como planejado no projeto) e foram tomadas as seguintes ações no servidor:
1. No nó bastion (Nimbus), foi utilizado o perfil dedicado de serviço **`iam`** (`/home/iam/.ssh/id_*.pub`).
2. A chave pública do perfil `iam` foi cadastrada no `/root/.ssh/authorized_keys` da máquina `200.18.99.87`:
   ```bash
   sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
   # Adição da chave pública
   sudo chmod 600 /root/.ssh/authorized_keys
   ```
3. O SSH do servidor foi configurado para permitir autenticação por chave para root:
   ```text
   PermitRootLogin prohibit-password
   ```
4. No GitHub Actions Secrets, o `USERNAME` configurado foi `iam`, garantindo que o Ansible na Nimbus utilize sua própria chave já autorizada para alcançar `root@200.18.99.87`.

---

## Postmortem 3: Restrição de Nomenclatura de Secrets no GitHub Actions (`GITHUB_*`)

### Sintomas
Ao tentar cadastrar o segredo da aplicação OAuth do GitHub com o nome `GITHUB_CLIENT_SECRET` nas configurações do repositório no GitHub, o painel retornava o erro:
> *"Secret names must not start with the GITHUB_ prefix."*

---

### Causa Raiz
O GitHub Actions reserva formalmente o prefixo `GITHUB_` para suas próprias variáveis de contexto interno da plataforma (como `GITHUB_TOKEN`, `GITHUB_SHA`, `GITHUB_REPOSITORY`, `GITHUB_ACTOR`). Segredos personalizados criados por usuários não podem usar esse prefixo.

---

### Solução Aplicada
1. Renomeou-se os segredos no [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) para o prefixo da aplicação:
   * **`KEYCLOAK_GITHUB_CLIENT_ID`**
   * **`KEYCLOAK_GITHUB_CLIENT_SECRET`**
2. No workflow, os valores são repassados ao Ansible sem violar as regras:
   ```yaml
   env:
     KEYCLOAK_GITHUB_CLIENT_ID: ${{ secrets.KEYCLOAK_GITHUB_CLIENT_ID }}
     KEYCLOAK_GITHUB_CLIENT_SECRET: ${{ secrets.KEYCLOAK_GITHUB_CLIENT_SECRET }}
   with:
     envs: KEYCLOAK_GITHUB_CLIENT_ID,KEYCLOAK_GITHUB_CLIENT_SECRET
     script: |
       EXTRA_VARS="-e github_client_id=$KEYCLOAK_GITHUB_CLIENT_ID -e github_client_secret=$KEYCLOAK_GITHUB_CLIENT_SECRET"
       ansible-playbook ... $EXTRA_VARS
   ```

---

## Postmortem 4: Disparidade de Identificação do Usuário no Incus (`oidc.claim`)

### Sintomas e Cenário
Usuários que se autenticavam via GitHub ou que possuíam e-mail preenchido no perfil do Keycloak falhavam na autorização do Incus com erro de permissão negada (403 Forbidden), enquanto usuários locais sem e-mail cadastrado conseguiam acesso normal.

---

### Investigação e Causa Raiz
1. **Comportamento Padrão do Incus:** Ao validar o token JWT emitido pelo Keycloak, o Incus busca a claim de identificação configurada em `oidc.claim`. Por padrão, se a claim `email` estiver presente no token, o Incus a utiliza como chave do usuário. Se a claim `email` estiver ausente, ele faz fallback para a claim `sub` (o UUID do Keycloak).
2. **Comportamento do Plugin do Keycloak (`keycloak-openfga-event-publisher`):** Ao escutar eventos de associação a grupos (`GROUP_MEMBERSHIP`), o plugin extrai o identificador do caminho REST do Keycloak (`/users/{id}/groups/...`). No Keycloak, esse `{id}` é **sempre o UUID interno** do usuário.
3. **O Conflito:**
   * **Usuário sem e-mail:** Incus usa `sub` (`<UUID>`) $\rightarrow$ OpenFGA possui tupla com `user:<UUID>` $\rightarrow$ **Autorizado!**
   * **Usuário com e-mail:** Incus usa `email` (`usuario@dominio.com`) $\rightarrow$ OpenFGA só possui tupla com `user:<UUID>` $\rightarrow$ **Acesso Negado!**

---

### Resolução e Melhores Práticas
1. **Padronização no Incus (`oidc.claim`):**
   Para eliminar a disparidade, o Incus deve ser configurado explicitamente para não depender de e-mails:
   * Para máxima consistência com o plugin atual (UUID):
     ```bash
     incus config set oidc.claim=sub
     ```
   * Para utilizar nomes legíveis e proteger a privacidade (PII) dos e-mails da equipe:
     ```bash
     incus config set oidc.claim=preferred_username
     ```
2. **Privacidade e Auditoria:** O uso de `preferred_username` foi documentado como a arquitetura ideal, pois:
   * Evita vazar e-mails pessoais de contas do GitHub nos logs de auditoria do Incus e no OpenFGA.
   * Funciona de forma idêntica para todos os usuários, independente de terem e-mail ou não.
   * Torna o output de comandos do Incus amigável para operadores humanos (`user: nicolas` em vez de um UUID ilegível).
