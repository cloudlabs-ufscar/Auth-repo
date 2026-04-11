# 1. Introdução
Este documento tem como objetivo analisar e discutir a arquitetura de identidade adotada na infraestrutura do CloudLabs, com foco nos mecanismos de autenticação e nos modelos de gestão de identidade aplicados a diferentes contextos computacionais.

Diante desse cenário, torna-se necessário compreender não apenas os mecanismos isolados de autenticação, mas sobretudo as diferentes abordagens arquiteturais que sustentam a gestão de identidade em nível de infraestrutura. Este trabalho propõe, portanto, uma análise comparativa entre tais abordagens, considerando seus benefícios, limitações e adequação a diferentes tipos de sistemas, com ênfase em ambientes Linux e aplicações web modernas.

---
# 2. Metodologia
A análise será conduzida em duas etapas complementares. Inicialmente, serão apresentadas e discutidas as principais abordagens de autenticação utilizadas em ambientes de infraestrutura, incluindo seus respectivos protocolos, modelos de funcionamento e implicações práticas, dividindo essa discussão em dois cenários: autenticação em sistemas Linux e em sistemas web. Para cada abordagem, serão examinados seus pontos fortes e limitações, bem como sua aplicabilidade em diferentes cenários, estabelecendo uma relação direta com os sistemas considerados neste estudo.

Na segunda etapa, será proposta uma arquitetura de identidade adequada ao contexto do CloudLabs, fundamentada na análise previamente desenvolvida. Serão justificadas as escolhas tecnológicas e arquiteturais adotadas, com base em critérios como segurança, escalabilidade, interoperabilidade e aderência a boas práticas consolidadas na área de gestão de identidade e acesso.

---
# 3. Primeira Parte

## 3.1 Autenticação em sistemas Linux
Historicamente, sistemas baseados no padrão POSIX estruturam seu modelo de autenticação a partir de identidades locais, nas quais cada usuário é representado por atributos fundamentais como _User ID_ (UID), _Group ID_ (GID), diretório pessoal (_home directory_), shell de login e, em cenários modernos, chaves públicas para autenticação via SSH. Esse modelo constitui a base do controle de acesso em sistemas Linux, sendo amplamente utilizado tanto em ambientes isolados quanto em infraestruturas distribuídas.

Entretanto, à medida que a complexidade dos ambientes computacionais aumenta — especialmente em cenários com múltiplos servidores, serviços distribuídos e integração com aplicações web — a gestão de identidades exclusivamente local torna-se insuficiente. Nesse contexto, surgem diferentes abordagens que permitem centralizar, federar ou abstrair o processo de autenticação, mantendo compatibilidade com o modelo POSIX enquanto ampliam suas capacidades.

A seguir, são apresentadas algumas das principais abordagens utilizadas para autenticação em sistemas Linux, destacando seus mecanismos de funcionamento, vantagens e limitações.

### 3.1.1 Sistema Local (Autenticação Nativa)
A forma mais básica de autenticação em sistemas Linux é realizada localmente, por meio de arquivos como `/etc/passwd`, `/etc/shadow` e `/etc/group`. Nesse modelo, as credenciais e atributos dos usuários são armazenados diretamente no sistema, sendo gerenciados por ferramentas nativas.

Essa abordagem apresenta como principal vantagem a simplicidade de implementação e independência de serviços externos. No entanto, sua escalabilidade é limitada, tornando-se inadequada para ambientes com múltiplos servidores, uma vez que exige replicação manual de usuários e não oferece mecanismos nativos de centralização ou Single Sign-On (SSO).

### 3.1.2 LDAP
O uso de diretórios baseados em LDAP (Lightweight Directory Access Protocol) introduz um modelo de centralização das identidades, no qual as informações dos usuários são armazenadas em um serviço de diretório acessível via rede por múltiplos sistemas.

Nesse modelo, sistemas Linux consultam o diretório para obter atributos como UID, GID e demais informações necessárias à autenticação e autorização, geralmente por meio de integrações com subsistemas como NSS (_Name Service Switch_) e PAM (_Pluggable Authentication Modules_).

A principal vantagem dessa abordagem reside na centralização e consistência das identidades, facilitando a gestão de múltiplos usuários em larga escala. Sistemas Linux podem consultar o LDAP como banco de usuários, contudo, por si só, também não provê mecanismos avançados de autenticação, como SSO ou autenticação baseada em tickets, sendo frequentemente combinado com outras tecnologias.

### 3.1.3 Autoridade Certificadora para SSH (SSH CA)
Nesse modelo, ao invés de confiar diretamente em chaves públicas distribuídas manualmente, os servidores passam a confiar em uma entidade central que assina certificados de acesso.

O usuário obtém um certificado temporário associado à sua chave pública, que é validado pelo servidor no momento da conexão. Esse modelo reduz significativamente a necessidade de gerenciamento manual de chaves e permite a implementação de políticas mais rigorosas, como expiração automática e controle centralizado de acesso.

Apesar de suas vantagens em termos de segurança e escalabilidade, essa abordagem introduz maior complexidade operacional e requer uma infraestrutura adicional para emissão e validação de certificados.

Além do mais, essa abordagem necessita combinação com outras tecnologias de manejo de usuários como o LDAP, já que ele por si só não configura usuários, apenas é uma maneira diferente de login.
### 3.1.4 Kerberos (Autenticação Baseada em Tickets)
O modelo baseado em Kerberos introduz um mecanismo de autenticação centralizado fundamentado na emissão de _tickets_ criptográficos por uma autoridade confiável. Nesse contexto, o usuário realiza autenticação inicial junto ao _Key Distribution Center_ (KDC) e, a partir disso, obtém credenciais temporárias que permitem o acesso a múltiplos serviços sem a necessidade de reenvio de senha.

Esse modelo é particularmente adequado para ambientes Linux distribuídos, pois permite _Single Sign-On_ (SSO) em nível de sistema operacional, além de evitar a exposição contínua de credenciais sensíveis na rede. Sua integração com diretórios, como LDAP, é comum, sendo este responsável pela persistência das identidades enquanto o Kerberos gerencia o processo de autenticação.

Como principais limitações, destacam-se a complexidade de configuração, a dependência de sincronização temporal rigorosa e a menor aderência a cenários modernos baseados em aplicações web e ambientes distribuídos na nuvem.

### 3.1.5 Identity-Aware Proxy e Access Brokers
Diferentemente do modelo de _Identity Provider_ (IdP), os _Identity-Aware Proxies_ e _access brokers_ atuam como intermediários no plano de acesso, e não apenas no plano de autenticação. Nesse modelo, o usuário não estabelece uma conexão direta com o servidor Linux; em vez disso, a conexão é iniciada contra um serviço intermediário, responsável por autenticar, autorizar e, então, encaminhar o acesso ao destino final.

Do ponto de vista operacional, esse modelo tem diferentes formas, sendo comumente um proxy que recebe a conexão antes e faz um túnel ssh conectando com a máquina.

## 3.2 Autenticação Web

### 3.2.1 Autenticação Baseada em Credenciais (Sessão)
Este modelo representa a abordagem mais tradicional, na qual o usuário fornece credenciais (tipicamente usuário e senha) diretamente à aplicação. Após validação, o sistema cria uma sessão associada ao usuário, geralmente mantida por meio de cookies.

Essa abordagem se destaca pela simplicidade de implementação e pelo controle direto da aplicação sobre o processo de autenticação. No entanto, apresenta limitações em termos de escalabilidade, especialmente em ambientes distribuídos, além de exigir cuidados adicionais com segurança, como proteção contra sequestro de sessão e ataques do tipo CSRF.

É mais adequada para aplicações monolíticas ou cenários com menor complexidade arquitetural.

### 3.2.2. Autenticação Baseada em Tokens
Nesse modelo, após a autenticação inicial, o usuário recebe um token (comumente um JWT, Jason Web Token) que passa a ser utilizado para autenticar requisições subsequentes. Diferentemente do modelo baseado em sessão, não há necessidade de armazenamento de estado no servidor, pois os tickets são verificados em real time e tem data de expiração, transformando em algo mais escalável para aplicações com muitos acessos.

A autenticação baseada em tokens é amplamente utilizada em APIs e arquiteturas de microserviços.

Como principal vantagem, destaca-se a escalabilidade e a independência entre serviços. Por outro lado, o controle sobre a revogação de acesso pode ser mais complexo, exigindo estratégias adicionais para gerenciamento de validade e segurança dos tokens.

### 3.2.3 Autenticação Federada com Single Sign-On (SSO)
A autenticação federada representa o modelo mais moderno e amplamente adotado em ambientes corporativos. Nesse caso, as aplicações não realizam autenticação diretamente, mas delegam essa responsabilidade a um provedor de identidade centralizado (_Identity Provider_), como o Keycloak.

Esse modelo é baseado em protocolos consolidados, como OAuth 2.0, OpenID Connect e SAML e pode ser visto como uma evolução do item anterior.

Entre seus principais benefícios estão a centralização da gestão de identidade, a melhoria da experiência do usuário e a possibilidade de integração com múltiplos sistemas via SSO. Além disso, esse modelo permite a adoção de mecanismos avançados de segurança, como autenticação multifator (MFA), que adiciona camadas adicionais de verificação (por exemplo, códigos temporários ou autenticação por dispositivo), elevando significativamente o nível de proteção contra acessos indevidos.

Como contrapartida, essa abordagem introduz maior complexidade arquitetural e dependência de um componente central, que deve ser altamente disponível e devidamente protegido.

---
# 4. Segunda Parte

## 4.1 Nosso Cenário
Diante das diferentes abordagens de autenticação apresentadas, torna-se necessário contextualizar as demandas específicas da infraestrutura do CloudLabs. Atualmente, o ambiente requer a coexistência de dois domínios principais de autenticação: sistemas baseados em POSIX (Linux) e sistemas web. Além disso, a infraestrutura depende de componentes auxiliares críticos, como VPN, autoridade certificadora para emissão de certificados TLS e servidor DNS, que juntos compõem a base de operação e comunicação do ambiente.

No estado atual, a autenticação em servidores Linux é realizada principalmente por meio de chaves públicas distribuídas manualmente por usuário. Embora funcional, esse modelo não é escalável e tende a gerar problemas operacionais recorrentes.

Adicionalmente, o principal ponto de acesso administrativo da infraestrutura, o gateway **Nimbus**, utiliza um modelo baseado em criação manual de usuários locais. Essa abordagem, apresenta limitações significativas em termos de manutenção, especialmente em cenários onde o sistema precisa ser recriado ou reinstalado, exigindo a reconfiguração completa de contas de usuários.

Para sistemas Web não temos nenhuma autenticação consistente hoje em dia, usamos a conta de administrador e todos tem acesso a tudo.

## 4.2 Centralização de Identidade com LDAP
Diante dessas limitações, o uso de um diretório centralizado para lidar com os diferentes protocolos e tipos de acesso (web e POSIX) como o LDAP surge como uma solução adequada para a gestão de identidades na infraestrutura. Por meio desse modelo, os usuários passam a ser definidos em um único ponto de controle, permitindo que múltiplos servidores consultem dinamicamente informações de autenticação e autorização.

Nesse cenário, os sistemas Linux podem ser configurados para utilizar o LDAP como fonte de identidade, permitindo a criação dinâmica de diretórios home e a associação automática de usuários ao ambiente de execução. Em muitos casos, também é possível padronizar o acesso utilizando um usuário local padrão (como “ubuntu”), enquanto o LDAP é utilizado principalmente para controle de identidade e autenticação.

Uma das principais vantagens dessa abordagem é a centralização da gestão de usuários, o que permite maior consistência entre sistemas e melhora a capacidade de auditoria. A partir desse modelo, torna-se possível rastrear com precisão qual usuário acessou qual máquina e em qual horário, o que é particularmente relevante em ambientes com requisitos de monitoramento e controle operacional.

O LDAP pode ser usado para consulta de acessos pelos servidores, mas é mais comum que ferramentas especializadas em acessos sejam usadas como o Kerberos, um protocolo já bem estabelecido. Sua dificuldade desvantagem é a complexidade impactada pelo Kerberos, que adiciona algumas camadas a mais de configuração para a infraestrutura inteira.

Outra desvantagem é o gerenciamento manual de chaves SSH. No mínimo, nesta arquitetura, precisaremos colocar cada chave pública de cada usuário no LDAP para centralizar o acesso SSH

## 4.3 Autenticação por SSH CA e Alternativas ao Modelo de Chaves Fixas
Como alternativa ao gerenciamento manual de chaves SSH, uma abordagem mais moderna consiste na utilização de uma Autoridade Certificadora para SSH (SSH CA).

Esse modelo pode ser implementado por diferentes soluções, como Step CA, HashiCorp Vault ou EJBCA.

As principais vantagens dessa abordagem incluem a eliminação da necessidade de distribuição manual de chaves, maior controle sobre tempo de validade das credenciais e centralização da política de acesso. Além disso, esse modelo reduz significativamente a complexidade operacional associada ao gerenciamento de múltiplas chaves distribuídas entre servidores.

Outro ponto relevante é a possibilidade de integração com um provedor de identidade centralizado, como o Keycloak, permitindo que a emissão de certificados seja condicionada a processos de autenticação mais robustos. Isso possibilita, por exemplo, a aplicação de autenticação multifator e o registro centralizado de eventos de acesso, reforçando a capacidade de auditoria da infraestrutura. Ademais, o keycloak tem integração excelente com monitoramento de usuário que está logando e serviço que está sendo logado. Porém, para os serviços de certificados, saber se o certificado SSH foi usado em acesso em alguma máquina vira uma tarefa difícil, já que não temos tanta precisão como teriamos no LDAP.

Além do mais, as atuais soluções já são integradas nativamente com emissão de certificados TLS, simplificando e centralizando todas as partes de certificados tanto TLS quanto SSH.

A principal desvantagem é se usarmos esse modelo é preciso achar soluções que integram a api do servidor DNS com a do CA, para que os challenges de certificados não sejam manuais e difíceis de serem feitos. Atualmente as soluções explicitadas acima tem integração, mas precisam de estudos mais detalhados.

## 4.4 SSO para sistemas Web
Considerando o conjunto de sistemas web presentes na infraestrutura — incluindo, entre outros, OpenStack, Incus, Grafana e Kubernetes — torna-se essencial a adoção de uma solução robusta de _Single Sign-On_ (SSO).

Nesse contexto, a autenticação federada não apenas simplifica a experiência do usuário, permitindo acesso unificado a múltiplos sistemas, como também centraliza o controle de identidade, auditoria e políticas de segurança. Soluções baseadas em autenticação isolada ou local tornam-se progressivamente inadequadas em arquiteturas modernas, sendo recomendadas apenas em cenários legados ou em aplicações que não oferecem suporte a protocolos de federação.

Dessa forma, o uso de um provedor de identidade centralizado, como o Keycloak, representa uma abordagem adequada para esse cenário, uma vez que oferece suporte a protocolos amplamente adotados na indústria, como OpenID Connect, OAuth 2.0 e SAML. Isso permite a integração consistente entre diferentes sistemas, mantendo um ponto único de controle de autenticação.

Além da autenticação, o Incus (e outras aplicações podem usar futuramente também), demanda um modelo de autorização detalhado para gerenciamento de recursos e operações sobre instâncias e containers. Para esse fim, a utilização de um sistema dedicado de controle de acesso baseado em políticas, como o OpenFGA, permite implementar um modelo de autorização mais expressivo e escalável, baseado em relações e regras de acesso.

# 5. Arquiteturas Propostas
Visto a discussão anterior, segue nesta seção propostas de modelos de gerenciamento de acesso:

## 5.1 FreeIpa Model
[Arquitetura-FreeIPA.md]

## 5.2 CA SSH
