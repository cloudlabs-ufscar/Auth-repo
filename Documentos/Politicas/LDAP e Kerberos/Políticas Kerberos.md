## 1. Definição de Realm e Interoperabilidade DNS

A infraestrutura opera sob um único Realm Kerberos, que serve como fronteira lógica de confiança para todas as identidades.

- **Realm Oficial:** `CLOUDLABS.UFSCAR`
    
- **Mapeamento de Domínio:** Deve haver uma correspondência biunívoca com o domínio DNS institucional `cloudlabs.ufscar`.

A grafia do Realm em letras maiúsculas é mandatória. Esta padronização é o que permite ao mecanismo de busca de domínio (_domain-to-realm mapping_) localizar corretamente os Centros de Distribuição de Chaves (KDC) e garantir a interoperabilidade entre os protocolos GSSAPI e TLS.

## 2. Taxonomia de Principals

Toda entidade capaz de se autenticar no Realm deve possuir um _Principal_ exclusivo, seguindo a estrutura padronizada:

| Categoria        | Formato do Principal          | Descrição                                                                         |
| ---------------- | ----------------------------- | --------------------------------------------------------------------------------- |
| **Utilizadores** | `utilizador@CLOUDLABS.UFSCAR` | Identidades humanas cadastradas no LDAP.                                          |
| **Hosts**        | `host/fqdn@CLOUDLABS.UFSCAR`  | Identidade da máquina para autenticação SSH e atualização de chaves.              |
| **Serviços**     | `HTTP/fqdn@CLOUDLABS.UFSCAR`  | Utilizado por serviços web (ex: Keycloak, FreeIPA Web UI) para negociação SPNEGO. |

## 3. Gestão de Ciclo de Vida e Tickets

A segurança do Kerberos baseia-se na emissão de tickets de curta duração, mitigando riscos de interceptação.

- **Política de Emissão:** Os _Ticket Granting Tickets_ (TGT) possuem validade limitada e suporte a renovação controlada, conforme configurado no KDC do FreeIPA.
    
- **Primeiro Acesso:** Utilizadores recém-criados recebem uma credencial temporária. O sistema exige a troca imediata de senha no primeiro login via protocolo Kerberos.
    
- **Métodos de Autenticação Posteriores:** Após a validação da identidade e troca de senha, o utilizador está apto a utilizar tanto o par de chaves SSH (integrado ao SSSD) quanto a senha definitiva para obtenção de novos tickets.
    

## 4. Contas de Contingência e Disaster Recovery

Para garantir a resiliência da infraestrutura em cenários de indisponibilidade do serviço de diretório ou falha total de rede, certas contas são mantidas fora do ecossistema Kerberos.

- **Contas Restritas:** `root` e `ubuntu` (ou outros usuários padrão de imagem).
    
- **Política:** Estas contas não possuem _Principals_ no Kerberos e permanecem estritamente locais.
    
- **Uso:** Reservadas exclusivamente para intervenções de emergência, manutenção de baixo nível e recuperação de desastres. O acesso a estas contas deve ser protegido por chaves SSH locais ou acesso físico/console.
    

## 5. Requisito Crítico: Sincronização de Tempo (NTP)

O protocolo Kerberos é altamente sensível a variações temporais devido à sua proteção nativa contra ataques de replicação (_replay attacks_).

- **Mecanismo:** Todos os hosts devem utilizar obrigatoriamente o serviço **Chrony** para sincronização de horário.
    
- **Tolerância:** Diferenças de tempo superiores a **5 minutos** (valor padrão do Kerberos) entre o cliente e o KDC resultarão na rejeição imediata dos tickets e falha total de autenticação.
    
- **Configuração:** Os servidores FreeIPA devem ser definidos como as fontes de tempo prioritárias para todos os hosts da malha privada.
    

## 6. Fluxo de Autenticação em Serviços HTTP

O Kerberos NÃO SERÁ UTILIZADO para autenticação de serviços HTTP. 