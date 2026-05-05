## 1. Domínio e Zona Autoritativa

A infraestrutura opera sob o domínio principal:

> **`cloudlabs.ufscar`**

Esta zona DNS é gerida de forma autoritativa pelo FreeIPA. Ela constitui o espaço de nomes interno oficial para a identificação de hosts, descoberta de serviços via registros SRV e integração de todos os componentes de autenticação.

## 2. Política de Nomenclatura e FQDN

A consistência de nomes é um requisito de segurança, não apenas uma convenção organizacional.

### 2.1. Unicidade e Clareza Funcional

Todo host deve possuir um nome DNS único e funcionalmente descritivo. A nomenclatura deve priorizar o serviço hospedado em detrimento de nomes arbitrários.

- **Padrão:** `<serviço>.<domínio>`

- **Exemplo:** `registry.cloudlabs.ufscar`, `ipa.cloudlabs.ufscar`.

### 2.2. Obrigatoriedade do FQDN (Fully Qualified Domain Name)

A configuração do sistema operativo deve refletir exatamente o registro DNS. O comando `hostnamectl set-hostname` deve ser utilizado para configurar o FQDN completo, e não apenas o _short name_.

- **Configuração Mandatória:** O _hostname_ local deve ser idêntico ao FQDN no DNS.
    
- **Impacto:** A discrepância entre o nome local e o registro DNS resulta em falhas críticas na negociação de tickets Kerberos e na validação de certificados TLS.

---

## 3. Registros DNS e Resolução Inversa

### 3.1. Forward DNS (Resolução Direta)

Todos os ativos devem possuir registros **A** (IPv4) ou **AAAA** (IPv6) válidos. A resolução direta é a base para a localização de serviços e comunicação entre sistemas distribuídos.

### 3.2. Reverse DNS (Resolução Inversa - PTR)

A existência de registros **PTR** consistentes para todos os endereços IP da infraestrutura é obrigatória.

A resolução inversa é utilizada por sistemas de segurança para verificar a autenticidade de uma conexão, garantindo que o IP de origem corresponde, de fato, ao hostname declarado.

---

## 4. Integração Crítica: DNS e Kerberos

O protocolo Kerberos possui uma dependência absoluta da infraestrutura de DNS. O funcionamento do SSO (_Single Sign-On_) em máquinas bare metal baseia-se na confiança mútua estabelecida através de nomes.

### 4.1. Localização de Serviços (SRV Records)

O Kerberos utiliza registros do tipo **SRV** no DNS para localizar dinamicamente os Centros de Distribuição de Chaves (KDC). A integridade destes registros na zona `cloudlabs.ufscar` é o que permite que um host recém-admitido identifique onde realizar a autenticação.

### 4.2. Canonicalização e Service Principals

Quando um utilizador solicita acesso a um serviço (ex: SSH), o Kerberos constrói o nome do serviço (_Service Principal Name - SPN_) baseando-se no FQDN do host de destino (ex: `host/registry.cloudlabs.ufscar@CLOUDLABS.UFSCAR`).

- Se o DNS direto falhar ou retornar um nome diferente do configurado no host, o ticket não será emitido.
    
- Se o DNS inverso (PTR) não corresponder ao FQDN, o processo de "canonicalização" falha, resultando em erros de "Server not found in Kerberos database", impossibilitando o acesso via SSO.
    

## 5. Diretrizes Operacionais

1. **Sincronização de Tempo:** Dado que o Kerberos e o DNS operam com janelas de validade, todos os hosts devem sincronizar os relógios via NTP com os servidores do FreeIPA.
    
2. **Gestão Centralizada:** Todas as entradas de DNS devem ser realizadas via interface ou CLI do FreeIPA para garantir que as chaves Kerberos e os registros de host permaneçam sincronizados automaticamente.
    
3. **Proibição de Nomes Genéricos:** Nomes como `localhost`, `servidor1` ou `teste` são proibidos na zona autoritativa para evitar colisões e ambiguidades na emissão de certificados.