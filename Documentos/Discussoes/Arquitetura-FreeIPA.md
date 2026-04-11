# Cenário
O presente documento visa discutir uma abordagem de SSO no cluster Cloud Labs.

No momento, não há uma maneira totalmente definida de controle e acesso em nosso cluster. Tanto sistemas Linux, quanto sistemas HTTP não tem um gerenciamento sólido de auth. Hoje em dia, quem tem acesso as máquinas nimbus, cirrus, c0c, c1c, inc1, inc2 e inc3 por meio de chave ssh, tem acesso a tudo.

###### Problemas
- Acesso irrestrito a todos os participantes. Isso implica que caso alguém mal intencionado ou que não saiba o que está fazendo, pode levar a comprometimento dos sistemas.
- O cluster é muito volátil, no sentido que ele sempre é formatado. Dessa forma, a maioria dos usuários perdem acesso, o que leva os administradores principais a ficarem um tempo adicionando todos de volta.
- Pouca observabilidade sobre quem está no sistema e mexendo com o que (discorrer mais depois)

### Solução Proposta
O presente documento visa propor uma solução para autenticação tanto para sistemas POSIX quanto para sistemas HTTP. Esses são os únicos tipos de acessos necessários, pois sistemas POSIX incluem as máquinas Linux (nossos servidores) e as aplicações utilizadas, tanto cloud native quanto as clouds em si, se baseiam em protocolo HTTP.

#### Glossário
- **LDAP:**
- **Keycloack:**
- **Kerberos:**
- **Certificate Authority**
- **DNS Server:**
- **PAM:**
- **SSSD:**
- **SSH:**
- **SAML:**
- **FreeIPA:**
- **Sudoers:**
- **Virtual Private Network:**
#### Topologia
![[Pasted image 20260326211057.png]]

Para que esta abordagem possa ocorrer de forma bem estruturada, é imprenscindivel uma VPN ativa no cluster Nimbus. Ela facilitará o papel do DNS interno entre outras coisas.

Nesta topologia, toda a administração de usuários (criação, remoção, edição de permissões) será centralizada pelo nosso LDAP.

##### Autenticação POSIX
![[Pasted image 20260326211118.png]]

Usuários (integrantes do CloudLabs) para se logar remotamente usarão o SSH. Para tirar a complexidade de um administrador de sistemas de criar uma nova conta para cada nova pessoa, basta adicionar seu usuário na base de dados do LDAP. Com isso, a pessoa já terá acesso (com a VPN, claro)  aos sistemas Linux e a se autenticar nas clouds (explicado mais tarde).

O Pluggable Authentication Module (PAM) serve como um plugin em como tratar os acessos nos sistemas. Configuraremos para que tanto a autenticação seja feita não pelo linux mas sim a partir do SSSD - este por sua vez será o responsável pela comunicação com o Kerberos -  quanto também criar diretórios `/home/` automático para cada usuário que tentar logar.

O SSSD se comunica com o kerberos, que por sua vez pedirá o nome de usuário e senha. O nome de usuário será sempre o nome colocado antes do `@` no comando de `ssh` (por exemplo, o usuário luiz logará com o comando `ssh luiz@nimbus`) e a senha o própio usuário digitará. O kerberos por baixo dos panos usa a base de dados do LDAP para conferir se o usuário existe e se ele está permitido logar no sistema.

##### Autenticação Web
![[Pasted image 20260326212133.png]]

O usuário que tentar logar na cloud (o Openstack ainda precisa ser revisitado para entender se ele suporta ou não) será redirecionado para o Keycloack, que apresentará um formulário pedindo a senha. Caso o usuário e senha estejam certos ele passará um token válido para entrar na Cloud por determinado tempo.

O Keycloack também puxa os usuários do LDAP. O protocolo kerberos também consegue funcionar como SSO para aplicações web (comunicação com o Incus acontece via de regra por requisições HTTP), porém o Keycloack é uma alternativa também muito boa, especializada para autenticação web com protocolos mais modernos como SAML e OAuth.

##### Ademais
Foi deixado de comentar sobre o Servidor DNS e a Certification Authority. Os dois também são imprescindíveis para esta topologia.

O DNS Server é necessário para que os servidores do FreeIPA sejam configurados bem, além de também ser importante para a escalabilidade do sistema (abordaremos mais tarde). Já o Certification Authority (CA) é importante para manter as comunicações tanto de protocolo `ldap` e `http` criptogradas (`ldaps://` e `https://`, respectivamente). Como estamos dentro de uma rede virtual, nã temos acesso a certificados Lets Encrypt, precisamos de uma autoridade para não dependermos de certificados auto-assinados 

Os serviços de DNS, Kerberos, LDAP e CA podem ser feitos com um só gerenciador chamado FreeIPA. A vantagem é conseguirmos configurar relativamente mais rápido os serviços. Desvantagem é que o servidor FreeIPA necessita estar em um sistema operacional baseado em Red Hat (Rocky, RHEL ou CentOS Stream).

![[Pasted image 20260326213240.png]]

---
#### Vantagens da Topologia
- **Base de dados centralizada:** um grande gargalo de precisar de múltiplos tipos de autenticação é precisar administrar diferentes bases de dados para cada um. Neste modelo, conseguimos ao máximo que o nosso LDAP seja nossa única fonte da verdade quando se trata dos usuários.
- **Escalabilidade:** caso esta abordagem siga em frente, é possível escalar rápido e facilmente, pois o freeIPA tem maneiras de sincronização de base de dados de Kerberos, DNS e LDAP. Dessa forma, usuários podem logar por mais de um server, pois háverá redundância.
  Também não é necessário um load balancer para distribuir o tráfego entre os diversos servers. Apenas com o DNS fazendo DNS Round Robin já garante uma boa distribuição das requisições.
  Este modelo de escalabilidade só é realmente necessário quando há muitos workloads distribuídos geograficamente.
- **Magalu Cloud:** por mais que o projeto vise construir uma infraestrutura soberana independente, o cluster Nimbus recorrentemente cai. Colocar infraestrutura crítica de acesso em ambientes instáveis pode vir a ser um problema no futuro. Desta forma, colocando os workloads de autenticação em VMs da MGC, teremos alta disponibilidade sem risco de ficarmos preso para fora.

### Metodologia
A seguinte metodologia visa proporcionar os próximos passos para a implementação final da estrutura de IAM:

1. Estruturação da rede e comunicação e comunicação entre serviços. Isso inclui a adição de uma VPN para o cluster.
2. Definição de comportamento de cada serviço, ou seja, definir quais são as configurações de cada serviço, ex: Qual será o domínio do DNS, faixa de IPs da VPN, como será configurado o REALM do Kerberos etc.
3. Definições de políticas de segurança, definir níveis de acesso e de ciclo de vida de usuários e a arquitetura de acessos para facilitar o gerenciamento das políticas e dos usuários no futuro.
4. Criação da topologia em imagens para documentação. Essas imagens devem conter toda a infraestrutura de acessos e todos os ciclos de vida dos usuários.
5. Discussões com o grupo para alinhar as políticas.
6. Uma vez discutido e aprovado, implementação das features. Os seguintes items podem mudar no futuro dependendo das discussões:
	6.1. Subir a VPN
	6.2 Criação da Autoridade Certificadora (CA). Garantir que as máquinas confiem no certificado da CA.
	6.3. Configuração do servidor DNS
	6.4. Criação e configuração do LDAP e seus usuários.
	6.5. Criação e configuração do Kerberos, Realm, etc.
	6.6. Configuração das máquinas para logarem apenas por LDAP/Kerberos.
	6.7. Criação e configuração do Keycloack.
	6.8. Configuração dos sistemas HTTP para logarem via Keycloack.

Todas as definições de comportamento de serviços e políticas serão consolidadas em documentos para todos terem acesso e visão geral da arquitetura.

O presente trabalho também visa estabelecer o conhecimento dos alunos participantes nessa área bem como os entregáveis em forma de scripts de provisionamento, documentos detalhados da arquitetura e de discussões e detalhes sobre.


#### Desafios
- Conseguir fazer um CA estável que possa fornecer certificados a todos (não trivial)
- Subir uma VPN (necessário arquitetar para que seja o mais simples e seguro possível)
- Rotas de rede estáveis e servidor DNS funcionando APENAS para os serviços e hosts nomeados
- Servidor FreeIPA estável
- Configuração do PAM, SSSD, SSHD_CONFIG para se conectar com o kerberos
- Detalhamento sobre o plano de escalada de privilégios (`sudo` e `root`) dos usuários. É necessário configurar arquivos como `/etc/sudoer`
- Estudo e detalhamento de grupos e usuários dentro do LDAP. Grupos podem influenciar em autorização de recursos tanto no Linux quanto no Incus
- Estudo aprofundado sobre o que o LDAP e o Keycloack pode entregar de regras e autorização. Como os dois se relacionam? O Keycloack pode adicionar mais regras para os usuários em seu próprio banco de dados?
- Conectar Incus ao Keycloack.
- O que é possível gerenciar de recursos? Como é dividido os tenants e como relacionar seus recursos com projetos diferentes e os usuários do keycloack?
- Conexão do prometheus, Grafana e outros recursos cloud native com o Keycloack.

---

#### Definições do Comportamento dos Componentes
##### CA
A autoridade certificadora, por definição, tem dois arquivos de chaves: uma pública e uma privada. Todas as máquinas que estiverem dentro da nossa VPN (isso inclui máquinas bare-metal de servidores, notebooks de usuários, máquinas-virtuais, etc) terão de acreditar na autoridade por meio de copiar o certificado público em `/var/usr/lib/ca-certificates`.

Os certificados gerados para os domínios devem ter validade por motivos de segurança. E também, por motivos de facilidade, priorizar intervalos de tempo grandes (1 ano).

Para máquinas que forem colocar aplicações de HTTP para HTTPS. Sempre priorizem subir sua infra com um nginx como reverse proxy. Ele facilita a manipulação dos certificados para suportar a criptografia.
**Exemplo:** subir o keycloack e fazer ele funcionar por https por conta própria é muito dificil. O nginx pode gerenciar o HTTPS e pode redirecionar o tráfego para o Keycloack.

##### DNS Server
O domínio da nossa infraestrutura levará o nome: **.cloudlabs.ufscar**.

TODOS os servidores devem ter nome de domínio, independentemente. A prioridade sempre é que o nome seja o mais claro possível (e.g. uma máquina que tem o Harbor, um container registry, deve levar o nome de domínio *registry.cloudlabs.ufscar*).

O DNS server deve fazer reverse DNS. Kerberos necessita disso para funcionar.

todos as máquinas devem ter o FQDN igual ao do seu respectivo nome de domínio. Isso é necessário em funcionamento de kerberos.

##### Kerberos
O Realm deve ser o mesmo que o nome de domínio só que em letras maiúsculas: **CLOUDLABS.UFSCAR**.

O kerberos não precisa guardar os usuários, quem faz isso é o LDAP. Porém, todos os hosts devem ser registrados no servidor kerberos. Então não se esqueça de fazer isso.

Todo host deve ter o mesmo nome que está gravado no domínio de DNS no servidor Kerberos (e.g. registry.cloudlabs.ufscar no kerberos será registry@CLOUDLABS.UFSCAR).

##### LDAP
O LDAP é nosso banco de usuários, é aqui que devemos adicionar ou deletar usuários. Por isso, será nesta seção que falaremos como será a configuração dos usuários.

###### Grupos
Criaremos diversos grupos para colocar os usuários. O grupo principal será o grupo **cloudlabs**, onde todos os usuários farão parte. Demais grupos deverão ser criados mediante discussão com o grupo. A ideia será dividir em cada subgrupo do projeto (e.g. usuários que mexem com monitoramento serão parte do grupo *monitoramento*).

O mesmo deve ser feito com as máquinas, que serão colocadas em grupos granulares também. Devemos pensar se as máquinas farão parte dos mesmos grupos dos usuários ou serão grupos separados somente para os hosts.

Entender diferença entre HBAC e RBAC.

##### Keycloack
O protocolo de autenticação e autorização será o OpenID Connect (OIDC).
##### Sistemas Linux

##### Sistemas HTTP


