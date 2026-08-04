#!/bin/bash

set -euo pipefail

STORE_ID=01KY7TAWJYJ5KR48TK19E1CT99

FGA_URL=https://cumulus.dc.ufscar.br:8080

GROUPS=(
    iam-project
    openstack-project
    network-project
    security-project
    monitoring-project
)

fga tuple write \
    --api-url="${FGA_URL}" \
    --store-id="${STORE_ID}" \
    "user:*" authenticated server:incus

fga tuple write \
        --api-url="${FGA_URL}" --store-id="${STORE_ID}" \
        group:"admin-project#member" admin server:incus

for projeto in "${GROUPS[@]}"; do
    echo "Mapeando: $projeto"
    fga tuple write \
        --api-url="${FGA_URL}" --store-id="${STORE_ID}" \
        group:"${projeto}#member" admin project:"${projeto}"
done