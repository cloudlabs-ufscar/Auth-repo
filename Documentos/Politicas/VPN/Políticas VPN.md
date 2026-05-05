## 1. Fundamentação e Objetivo

Dada a dispersão geográfica e lógica da infraestrutura, a comunicação administrativa e o tráfego entre serviços internos ocorrem obrigatoriamente através de túneis criptografados baseados no protocolo **WireGuard**. Esta abordagem garante o isolamento do tráfego interno em relação à internet pública e provê uma camada de transporte segura para o tráfego LDAP, Kerberos e de gestão de sistemas.

## 2. Topologia e Segmentação de Rede

A rede é estruturada em uma topologia híbrida que interconecta dois centros de dados distintos através de gateways dedicados.

### 2.1. Segmentos de Rede Privada

A infraestrutura está dividida nos seguintes blocos de endereçamento:

- **Gateway Magalu Cloud (MGC):** Rede 10.0.35.0/24.
    
- **Gateway UFSCar (Nimbus):** Rede 10.0.36.0/24.
    
- **Redes de Serviço (Backend):**
    
    - `192.168.100.0/24`: Cluster Incus (UFSCar).
        
    - `192.168.200.0/24`: Cluster OpenStack (UFSCar).
        
    - `172.18.0.0/16`: Rede privada interna da Magalu Cloud. 

### 2.2. Arquitetura de Roteamento (Split Tunnel)

A VPN opera sob o princípio de **Split Tunnel**, onde apenas o tráfego destinado aos prefixos internos é roteado através do túnel. Os gateways atuam como pontos de encaminhamento (_forwarding_) explícito.

- **Atores da VPN:** Apenas os gateways (MGC e UFSCar) e os dispositivos finais dos utilizadores possuem endereços IP dentro da interface WireGuard.
    
- **Isolamento de Hosts:** As máquinas de carga de trabalho (nós de computação) permanecem em suas redes internas e não possuem IPs de VPN, sendo acessíveis apenas através do roteamento provido pelos gateways.

## 3. Configuração de Clientes e Roteamento

Para garantir a comunicação bidirecional e o acesso aos serviços, o parâmetro `AllowedIPs` nas configurações dos pares (_peers_) deve ser rigorosamente definido com as rotas aprovadas. A propagação de tráfego não autorizado é mitigada pela ausência de rotas fora deste escopo.

## 4. Resolução de Nomes (DNS) via VPN

A conectividade provida pela VPN é integrada ao sistema de nomes de domínio (DNS) interno para assegurar a operabilidade do Kerberos.

- **Resolvedor Primário:** Todo cliente VPN deve, obrigatoriamente, utilizar o servidor DNS interno da infraestrutura (`cloudlabs.ufscar`).
    
- **Resiliência (Fallback):** São utilizados os resolvedores públicos `1.1.1.1` e `8.8.8.8` apenas como contingência para tráfego externo.

## 5. Gestão de Identidades VPN e Provisionamento

O acesso de utilizadores à VPN é individualizado e vinculado à identidade do sujeito no diretório central.

### 5.1. Atribuição de Endereços

Os utilizadores autorizados recebem endereçamento fixo dentro do intervalo **10.0.36.0/24**. Cada perfil de conexão é composto por:

1. Chave pública individual (WireGuard Peer).
    
2. Endereço IP estático e único.
    
3. Associação nominal ao utilizador correspondente no LDAP para fins de auditoria.

### 5.2. Processo de Criação e Revogação

A gestão técnica das interfaces e chaves no gateway Nimbus (UFSCar) é realizada via script de automação (`wireguard-install.sh`).

- **Criação:** Novos utilizadores devem ser gerados no gateway da UFSCar, garantindo que o perfil gerado contenha as rotas de ambos os ambientes (MGC e UFSCar).
    
- **Revogação:** Em caso de desligamento ou comprometimento de chaves, o par deve ser removido imediatamente do arquivo de configuração do gateway para cessar a conectividade.
    

## 6. Política de Segurança: Conectividade vs. Autorização

É fundamental distinguir o papel da VPN na stack de segurança:

1. **VPN (Conectividade):** Concede o canal de comunicação e transporte de pacotes. Estar conectado à VPN não implica possuir acesso aos servidores.
    
2. **LDAP/HBAC (Autorização):** Define se o utilizador autenticado via VPN possui permissão para realizar login ou executar comandos em um determinado host.
    
3. **Firewall (Controle de Acesso):** Os hosts aplicam as regras finais de filtragem de pacotes, restringindo o tráfego apenas a origens conhecidas dentro da malha VPN.

---

### Resumo das Camadas de Acesso:

- **Camada 1:** VPN WireGuard (Permite chegar ao IP do servidor).
    
- **Camada 2:** Kerberos/LDAP (Valida quem é o utilizador).
    
- **Camada 3:** HBAC (Valida se o utilizador pode entrar naquele servidor específico).
    
- **Camada 4:** SUDO/RBAC (Valida o que o utilizador pode fazer lá dentro).