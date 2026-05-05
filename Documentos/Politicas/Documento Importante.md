O presente documento visa direcionar sobre a topologia de autorização em nossa arquitetura de IAM.

Na presente infraestrutura, lidamos com diferentes níveis de acessos que definimos em dois principais objetivos:
- Acesso em máquinas (tanto virtuais quanto bare metal, desde que façam parte de nossa infraestrutura de cloud).
- Acesso à serviços (geralmente, mas não necessariamente, baseados em sistemas HTTP) como nossos serviços de cloud e de monitoramento.

Com este escopo e nossa arquitetura de IAM definidos (caso não tenha entendimento da arquitetura, leia os documentos da seção `~/Documentos/Discussoes` deste repositório) se torna necessário neste momento fazer o design da topologia de autorização nos diferentes sistemas e como integrar eles para ser o mais redundante possível e a maneira mais eficiênte de opera-lo sem complexar mais do que necessario.

Este documento visa proporcionar este design.

## Primeiras Observações

Antes de entrarmos nas definições em si, é preciso esclarecer alguns pontos para podermos tomar partida.

Como dito anteriormente, temos dois objetivos principais de acessos. Em nossa arquitetura esses dois objetivos tem formas e protocolos de autenticação diferente (Sistemas Operacionais usam LDAP/Kerberos e serviços usam Keycloak/OpenFGA/OpenID). Além disso, a **autorização**, e implementação deste autorização, de cada serviço é feito diferente. Por exemplo, a autorização que queremos fornecer no OpenStack é quais acessos a quais projetos e recursos cada pessoa/grupo podem usar, já a autorização no Grafana é para quais métricas o usuário/grupo pode ter acesso de ver. Desta forma, precisamos pensar em processos de autorização de usuários para cada serviço e como implementaremos no serviço em si isso.

> **Atenção:**
>A proposta do OpenFGA é ter uma autorização unificada em um só software e todos os serviços consumirem dele. Porém, este modelo não foi aderido formalmente em todos os serviços que usamos. O OpenStack, por exemplo, não suporta.
>Por isso, este modelo será usado apenas em serviços que o suportam (como por exemplo, o Incus). Já nos demais, será necessário implementações nos próprios softwares dos serviços.
>Está parte prática de implementação não será aborda neste documento.

Outra observação que é preciso fazer é a federação LDAP e Keycloak. Para acesso aos hosts, será feito um modelo RBAC entre os host groups e user groups que serão criados no LDAP. Apesar da federação puxar os grupos dos usuários e transformar em roles, não é interessante usarmos esses grupos para a autorização dos serviços, visto que precisaremos de vários grupos para diferentes autorizações de serviços.

A maneira mais eficiente é fazer um sistema que o Keycloak irá puxar diversas roles para os usuários a partir de seus grupos. Desta forma não precisará de duplicação de grupos tanto no Keycloak quanto no LDAP e vamos conseguir uma base boa de abstração e de operabilidade. 

## Definição de Políticas de Grupos

### Modelo de Grupos e suas Relações LDAP

Esta seção visa modelar como os grupos de usuários e de hosts serão construídos, bem como seu relacionamento em RBAC. Todas as definições e justificativas de cada um poderá ser encontrado por meio da seguinte tabela:

| Definição    | Breve Descrição                             | Link |
| ------------ | ------------------------------------------- | ---- |
| Users Groups | Definição dos Grupos de Usuários            |      |
| Hosts Groups | Definição dos Grupos de Hosts               |      |
| Modelo RBAC  | Definição da relação entre Hosts e Usuários |      |

### Modelo de Roles e suas relações Keycloak 

Esta seção visa modelar as roles dos usuários federados do LDAP. Isto é, definir quais roles existirão, qual modelo