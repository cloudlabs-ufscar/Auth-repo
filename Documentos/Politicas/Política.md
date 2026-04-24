## Criação de Entidades via LDAP
Entidades compreendem todas as identidades digitais administradas pela infraestrutura, incluindo usuários, grupos e hosts. O diretório LDAP constitui a fonte central de verdade para cadastro, atributos e associação entre entidades.

Todas as entidades deverão ser criadas e mantidas exclusivamente no diretório central.

### Criação de Usuários
Todos os usuários devem ser escritos em letra minúscula.
#### Usuários Internos
Todos os membros internos do CloudLabs deverão possuir:
- associação obrigatória ao grupo `cloudlabs`
- associação ao respectivo subgrupo de pesquisa
- associação ao grupo `docentes`, quando aplicável
- chave pública SSH cadastrada no diretório
- atributos POSIX válidos (`uid`, `gid`, `home`, `shell`)
	- `shell`: `/bin/bash/` (sempre)

Permissões administrativas serão concedidas por padrão, sendo atribuídas a todos membros do grupo **cloudlabs**.

#### Usuários Externos
Usuários externos deverão possuir:
- associação ao grupo `externo`
- chave pública SSH cadastrada
- acesso restrito aos hosts explicitamente autorizados

### Criação de Hosts
Todos os hosts deverão possuir:
- associação ao grupo global `cloudlabs-hosts`
- associação ao hostgroup correspondente ao serviço exercido
- principal Kerberos próprio
- keytab local para autenticação

Todo hostgroup deve sempre acabar com um sufixo `-hosts` e deve ser inteiramente escrito em letras minúsculas. Os hostgroups serão os seguintes:
- cloudlabs-hosts
- monitoring-hosts
- incus-hosts
- openstack-hosts
- gateway-hosts

## Virtual Private Network (VPN)
Devido à distribuição da infraestrutura entre ambientes distintos, incluindo recursos hospedados na Magalu Cloud e no cluster Nimbus da Universidade Federal de São Carlos, toda comunicação administrativa e de serviços internos deverá ocorrer obrigatoriamente por meio de uma VPN corporativa baseada em WireGuard.

A VPN constitui a malha privada de interconexão da infraestrutura, sendo responsável por:
- transporte seguro entre redes privadas distintas
- acesso administrativo aos hosts internos
- resolução simplificada de endereçamento entre ambientes
- isolamento do tráfego interno em relação à Internet pública

### Segmentação de Rede
A topologia atual encontra-se segmentada da seguinte forma:
- gateway dedicado na Magalu Cloud com rede privada `10.0.35.0/24`
- ambiente Nimbus com rede privada `10.0.36.0/24`
- interconexão entre os dois ambientes via peers WireGuard autenticados por chave pública

Cada segmento mantém roteamento privado através da VPN, permitindo comunicação controlada entre hosts autorizados.

### Rotas Permitidas
As rotas anunciadas atualmente são:
- `10.0.35.0/24` (rede VPN gateway mgc)
- `10.0.36.0/24` (rede VPN gateway UFSCar)
- `192.168.100.0/24` (rede privada Incus cluster UFSCar)
- `192.168.200.0/24` (rede privada OpenStack UFSCar)
- `172.18.0.0/16` (rede privada mgc)

Essas rotas deverão permanecer explicitamente definidas no parâmetro `AllowedIPs`, evitando propagação indevida de tráfego não autorizado.

### Resolução DNS
Todos os clientes VPN deverão utilizar resolução DNS controlada, priorizando:
- servidor DNS interno da infraestrutura
- fallback público controlado:
    - `1.1.1.1`
    - `8.8.8.8`

Sugere-se priorizar o resolvedor interno como primeira opção, garantindo resolução consistente de hosts internos e serviços autenticados.

### Endereçamento de Usuários VPN
Todos os usuários autorizados na VPN receberão endereçamento dedicado dentro do intervalo:

- `10.0.36.0/24`

Cada identidade VPN deverá possuir:
- chave pública individual
- endereço IP fixo
- associação explícita ao usuário LDAP correspondente

### Política de Acesso VPN
O acesso VPN não implica acesso irrestrito à infraestrutura.

Todo tráfego originado por usuários VPN deverá permanecer sujeito às políticas de autorização já definidas para:
- autenticação SSH
- grupos LDAP
- regras de firewall

Ou seja:
- VPN concede conectividade
- LDAP define autorização
- hosts aplicam controle final de acesso

### Split Tunnel
O gateway VPN atuará como ponto autorizado de roteamento entre segmentos privados, mantendo forwarding explícito apenas para redes aprovadas.

Isso implica que apenas o gateway da mgc e da UFSCar e os usuários terão realmente IP na VPN. As outras máquinas devem estar em suas respectivas redes internas.

### Criação de Usuários na VPN
Usamos o script shell `wireguard-install.sh` que está disponível na internet a partir do seguinte link: https://github.com/angristan/wireguard-install.git

Usuários serão criados e revogados  por meio desse script no gateway da UFSCar (nimbus).

## Certificados e Autoridade Certificadora (CA)
A CA é nossa autoridade para emitir certificados para comunicação criptografada dos serviços. Por isso, TODOS os servidores e máquinas de usuários devem colocar no path `/usr/local/share/ca-certificates` o certificado público da CA, para dessa forma eles confiarem em seus certificados

### Criptografia TLS para Serviços
Todo serviço HTTP interno deve preferencialmente expor TLS via reverse proxy centralizado.
**Exemplo:** subir o keycloack e fazer ele funcionar por https por conta própria é muito dificil. O NGINX pode gerenciar o HTTPS e pode redirecionar o tráfego para o Keycloack.

## DNS Server e Domínios
O domínio principal da infraestrutura será:

**cloudlabs.ufscar**

Este domínio constitui a zona DNS interna oficial utilizada para identificação de hosts, descoberta de serviços e integração entre componentes de autenticação e segurança.

### Nomeação de Hosts
Todo host pertencente à infraestrutura deverá possuir obrigatoriamente:
- nome DNS próprio
- nome único dentro da zona
- FQDN válido

A nomenclatura deverá priorizar clareza funcional e previsibilidade operacional.

Exemplo: `registry.cloudlabs.ufscar`

Sempre que possível, o nome deverá refletir diretamente o serviço principal hospedado.

### FQDN Obrigatório
Todos os hosts deverão operar com seu hostname local exatamente igual ao respectivo FQDN configurado em DNS.

Exemplo:
```bash
hostnamectl set-hostname registry.cloudlabs.ufscar
```

A consistência entre hostname local e FQDN é obrigatória para:
- funcionamento correto do Kerberos
- emissão de certificados
- autenticação de serviços
- resolução consistente entre sistemas distribuídos

### Forward DNS
Todos os hosts deverão possuir registros DNS diretos (`A` ou `AAAA`) válidos apontando para seus respectivos endereços IP internos.

A resolução direta deverá ser mantida exclusivamente pelo servidor DNS autoritativo da infraestrutura.

### Reverse DNS
Todos os endereços IP internos deverão possuir registros reversos (`PTR`) consistentes.

A resolução reversa é obrigatória para:
- autenticação Kerberos
- validação de serviços

A ausência de reverse DNS poderá causar falhas de autenticação em serviços dependentes de principal Kerberos.

## Configurações Kerberos
A infraestrutura utilizará Kerberos como mecanismo central de autenticação para usuários, hosts e serviços internos.

Toda a infraestrutura deverá operar sob um único realm Kerberos:

**CLOUDLABS.UFSCAR**

O realm deverá manter correspondência direta com o domínio DNS institucional:
- domínio DNS: `cloudlabs.ufscar`
- realm Kerberos: `CLOUDLABS.UFSCAR`

A padronização entre DNS e realm é obrigatória para garantir interoperabilidade entre autenticação, resolução de nomes e emissão de tickets.

### Principals
Toda identidade autenticável deverá possuir principal próprio.
- **usuários:** `usuario@CLOUDLABS.UFSCAR
- **hosts:** `host/fqdn@CLOUDLABS.UFSCAR
- **serviços:** `HTTP/fqdn@CLOUDLABS.UFSCAR

### Política de Tickets
Os tickets emitidos deverão possuir validade limitada e renovação controlada.

### Primeira Autenticação de Usuários
Usuários recém-criados receberão senha inicial temporária.

No primeiro login:
- autenticação via Kerberos obrigatória
- troca imediata de senha exigida

Após a troca:
- autenticação por senha
- ou autenticação por chave pública SSH

### Restrições
As contas locais:
- `root`
- `ubuntu`

não deverão possuir principal Kerberos e permanecerão exclusivamente locais.

Essas contas serão reservadas para contingência e disaster recovery.

### Sincronização de Horários
Todos os hosts deverão manter sincronização precisa de horário via NTP.

Diferenças de tempo superiores ao limite aceito pelo Kerberos resultarão em falha de autenticação.

Usar **chrony** para essa função.

## Autenticação POSIX
A autenticação de usuários em servidores Linux da infraestrutura será centralizada e baseada em identidades POSIX federadas por meio de diretório LDAP e autenticação Kerberos.

Todo acesso interativo aos servidores deverá ocorrer prioritariamente por meio de openSSH, utilizando autenticação centralizada contra o serviço Kerberos, cuja base de identidades é mantida no diretório LDAP institucional.

Toda máquina Linux integrante da infraestrutura deverá obrigatoriamente aderir a este modelo de autenticação.

### Modelo de Funcionamento
O fluxo de autenticação adotado segue a seguinte cadeia:
- o usuário inicia conexão SSH com o host de destino
- o host consulta a identidade do usuário no diretório LDAP
- a autenticação é validada junto ao servidor Kerberos
- uma vez autenticado, o acesso é liberado conforme regras de autorização locais

```yml
SSH → NSS → SSSD → LDAP → Kerberos → PAM → shell
```

### Identidades POSIX
Todo usuário autenticado deverá possuir identidade POSIX válida no diretório LDAP, incluindo:

- `uid`
- `gid`
- `homeDirectory`
- `loginShell`

O nome de login deverá ser único e consistente em toda a infraestrutura.

**Exemplo:** Se um membro possuir o identificador `dudu`, esse mesmo login deverá ser utilizado em todos os hosts autorizados.

```sh
ssh dudu@ip-host
```

O usuário poderá escolher entrar por senha Kerberos ou por chave pública, caso o mesmo coloque a chave no LDAP ou em `~/.ssh/authorized_keys` do seu diretório home da máquina.

### Contas Locais
Cada servidor deverá manter apenas duas contas POSIX locais:

- `root`
- `ubuntu` (conta padrão criada pelo SO. Pode mudar a depender do Sistema Operacional)

Essas contas permanecerão exclusivamente locais e não deverão ser federadas ao LDAP ou ao Kerberos. Elas são reservadas para contigência operacional e disaster recovery.

Todos os demais usuários deverão existir exclusivamente no diretório LDAP.

Acesso ssh a essas duas contas deve ser estritamento feito apenas por usuários administradores. Estes, por sua vez terão suas chaves públicas no `authorized_keys` de cada conta.

Além disso, esta conta deve ter uma chave de recuperação disponível para os administradores.

### Integração Local com o Kerberos e LDAP: SSSD
Os hosts para conseguirem se comunicar com os serviços de autenticação precisam de um software chamado **SSSD**. Este é responsável por: 

- consulta de identidades no LDAP
- autenticação contra Kerberos
- cache local de credenciais, suporte a login offline temporário (caso o usuário esteja na nimbus presencialmente na UFSCar)

### Pluggable Authentication Modules (PAM)
O PAM é responsável por encadear e sistematizar a autenticação no sistema. Isso quer dizer que ele é quem direciona o acesso SSH do usuário para o SSSD ou para autenticação local, dependendo da conta.

O PAM em nossa infraestrutura também é responsável pela criação dinâmica de diretórios `/home`. Isso garante que usuários LDAP tenham ambiente local criado no primeiro login sem necessidade de provisionamento manual.

### Proteção contra Força Bruta
Para mitigação de ataques de força bruta contra autenticação por senha, todos os hosts deverão executar **Fail2ban**. O fail2ban é um software que praticamente não consume recurso e é uma excelente opção para mitigação de ataques de força bruta.

Política inicial:
- máximo de 5 tentativas falhas
- bloqueio automático por IP

Tempo de bloqueio:
- mínimo: 2 horas
- máximo: 24 horas

Os tempos poderão ser ajustados conforme criticidade do host.

### SSH
O SSH deve estar habilitado para autenticação de senha e chave pública.

### Política de SUDO
Essa deve ser uma seção com constante atenção e modificação.

Por default, deixaremos neste primeiro momento que todos os usuários do cloudlabs tenham acesso a root. Basta pertencer ao grupo **cloudlabs** que já está apto tanto a entrar nas máquinas quanto escalar privilégios.

## Autenticação HTTP e Keycloak
A autenticação de aplicações web internas e serviços acessados por protocolo HTTP será centralizada por meio do Keycloak, que atuará como provedor central de identidade (Identity Provider – IdP) da infraestrutura.

Enquanto o Kerberos fornece autenticação para sistemas operacionais e serviços de infraestrutura, o Keycloak será utilizado como camada de autenticação para serviços web HTTP.

Ainda sim, por meio de User Federation, o fornecedor de identidades ainda será o LDAP. Isso garante unicidade de credenciais, sincronização central de grupos e eliminação de contas duplicadas para gerenciar.

### Protocolos Suportados
A autenticação HTTP deverá utilizar preferencialmente:
- OpenID Connect (OIDC)
- OAuth2

Sempre que necessário, poderá haver suporte a:
- SAML

Os protocolos adotados dependerão da compatibilidade do serviço integrado.