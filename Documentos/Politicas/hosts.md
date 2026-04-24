Este arquivo visa documentar todos os hosts de nossa infraestrutura. Isso serve para usarmos de base para o ansible e para nos guiarmos sobre nomes e IPs padronizados (lembrando que máquinas na MGC são sussetíveis a mudarem de IP).

> **Atenção**
> IPs dos gateways tem IPs de VPN, é imprenscindível que a VPN esteja de pé!

## HostGroups

| HostGroup           | Function                                                |
| ------------------- | ------------------------------------------------------- |
| cloudlabs-hosts     | Grupo geral para todos os hosts da nossa infraestrutura |
| iam-hosts           | Grupo das máquinas pertencentes a infra de auth         |
| openstack-hosts     | Todas as máquinas que configurarão OpenStack            |
| incus-hosts         | Todas as máquinas que configurarão cluster incus        |
| incus-cirrus-hosts  | Máquinas do cluster incus cirrus                        |
| incus-stratus-hosts | Máquinas do cluster incus stratus                       |
| monitoring-hosts    | Máquinas que farão a função de monitoramento            |

## Hosts

| DNS Name (cloudlabs.ufscar)   | IPv4                             | zone   | Function        |
| ----------------------------- | -------------------------------- | ------ | --------------- |
| freeipa.cloudlabs.ufscar      | 172.18.1.23                      | MGC    | freeipa server  |
| keycloak.cloudlabs.ufscar     | 172.18.3.105                     | MGC    | keycloak server |
| gateway-mgc.cloudlabs.ufscar  | 201.54.18.177,<br>10.0.35.1      | MGC    | Gateway MGC     |
| nimbus.cloudlabs.ufscar       | 200.18.99.86,<br>10.0.36.1       | UFSCar | gateway UFSCar  |
| inc1-cirrus.cloudlabs.ufscar  | 192.168.200.85,<br>192.168.69.23 | UFSCar | incus 1 cluster |
| inc2-cirrus.cloudlabs.ufscar  | 192.168.200.88,<br>192.168.69.35 | UFSCar | incus 1 cluster |
| inc3-cirrus.cloudlabs.ufscar  | 192.168.200.89,<br>192.168.69.36 | UFSCar | incus 1 cluster |
| inc4-stratus.cloudlabs.ufscar | 192.168.200.82,<br>192.168.69.22 | UFSCar | incus 2 cluster |
| inc5-stratus.cloudlabs.ufscar | 192.168.200.83,<br>192.168.69.37 | UFSCar | incus 2 cluster |
| inc6-stratus.cloudlabs.ufscar | 192.168.200.84,<br>192.168.69.38 | UFSCar | incus 2 cluster |

## Relação entre Hosts e HostGroups

| DNS Name (cloudlabs.ufscar)   | HostGroups                                        |
| ----------------------------- | ------------------------------------------------- |
| freeipa.cloudlabs.ufscar      | cloudlabs-hosts, iam-hosts                        |
| keycloak.cloudlabs.ufscar     | cloudlabs-hosts, iam-hosts                        |
| gateway-mgc.cloudlabs.ufscar  | cloudlabs-hosts, iam-hosts                        |
| nimbus.cloudlabs.ufscar       | cloudlabs-hosts,                                  |
| inc1-cirrus.cloudlabs.ufscar  | cloudlabs-hosts, incus-hosts, incus-cirrus-hosts  |
| inc2-cirrus.cloudlabs.ufscar  | cloudlabs-hosts, incus-hosts, incus-cirrus-hosts  |
| inc3-cirrus.cloudlabs.ufscar  | cloudlabs-hosts, incus-hosts, incus-cirrus-hosts  |
| inc4-stratus.cloudlabs.ufscar | cloudlabs-hosts, incus-hosts, incus-stratus-hosts |
| inc5-stratus.cloudlabs.ufscar | cloudlabs-hosts, incus-hosts, incus-stratus-hosts |
| inc6-stratus.cloudlabs.ufscar | cloudlabs-hosts, incus-hosts, incus-stratus-hosts |
