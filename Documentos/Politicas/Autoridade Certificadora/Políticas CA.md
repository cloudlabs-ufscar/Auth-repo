## 1. O Papel da CA no Ecossistema

A CA do FreeIPA (baseada em Dogtag) atua como a **Raiz de Confiança** de toda a nossa infraestrutura. Ela é responsável por emitir, renovar e revogar certificados digitais para hosts e serviços, eliminando a dependência de CAs externas para tráfego interno e garantindo criptografia ponta-a-ponta.

## 2. Distribuição de Confiança (Trust Store)

Para que os certificados emitidos sejam validados, o certificado público da CA deve estar presente em todos os ativos da rede.

- **Procedimento em Linux:** O certificado raiz deve ser copiado para `/usr/local/share/ca-certificates/cloudlabs-ca.crt` (serve apenas para servidores Ubuntu, outros tipos serão outros paths).
    
- **Atualização:** Após a cópia, deve-se executar obrigatoriamente o comando `update-ca-certificates` para atualizar o *bundle* do sistema.
    
- Esta política aplica-se a todos os servidores bare metal, containers persistentes e máquinas de utilizadores (estações de trabalho) integradas ao grupo.

- Todos os computadores de servidores tem que implementar este certificado antes de subir qualquer serviço neles.
    

## 3. Políticas de Ciclo de Vida do Certificado

Dada a natureza dinâmica de um grupo de pesquisa, estabelecemos políticas que equilibram segurança com agilidade operacional.

### 3.1. Validade e Renovação

- **Tempo de Vida Standard:** Todos os certificados de serviço e host terão validade de **1 ano (365 dias)**.
    
- Um ano permite uma rotação de chaves saudável sem sobrecarregar a equipa com renovações mensais, sendo ideal para o ciclo de vida de projetos de pesquisa.
    
- **Automação (Certmonger):** É mandatário o uso do `certmonger` (comando `ipa-getcert`) em todos os servidores. Ele é o responsável por monitorizar a validade e solicitar a renovação automática à CA antes do vencimento, evitando indisponibilidade de serviços por certificados expirados.

### 3.2. Revogação

Um certificado deve ser revogado imediatamente se:

1. A chave privada do host ou serviço for comprometida.
    
2. O host for removido permanentemente da infraestrutura (`ipa host-del`).
    
3. O serviço for descontinuado.

---

## 4. Estratégia de Implementação TLS

Gerir TLS nativamente em cada aplicação pode ser um pesadelo de configuração (ex: Java KeyStores no Keycloak). Por isso, adotamos uma estratégia de **Terminação TLS via Proxy Reverso**.

Sempre que possível, o serviço (Keycloak, Grafana, OpenFGA) deve rodar em HTTP no _localhost_ ou em uma rede isolada, enquanto um NGINX atua como a face pública criptografada.

- **Vantagem:** O NGINX concentra a gestão dos certificados em um único local e formato (arquivos `.pem` ou `.crt`/`.key`).
    
- **Isolamento:** O tráfego pesado e complexo de cifras TLS é processado pelo NGINX, que é altamente otimizado para isso.
    

### 4.2. Identificação de Serviços (SAN)

Os certificados devem ser emitidos utilizando o **Subject Alternative Name (SAN)** para garantir que múltiplos nomes (ex: `sso.cloudlabs.org` e `keycloak.internal.cloudlabs.org`) sejam validados pelo mesmo certificado, se necessário.