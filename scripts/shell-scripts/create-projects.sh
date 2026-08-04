#!/bin/bash

PROJECTS=(
    iam-project
    openstack-project
    network-project
    security-project
    monitoring-project
)

RESOURCES_CPU_PER_PROJECT=(
    10
    20
    10
    10
    10
)

RESOURCES_MEMORY_PER_PROJECT=(
    "30GiB"
    "100GiB"
    "30GiB"
    "30GiB"
    "30GiB"
)

for i in "${!PROJECTS[@]}"; do
    incus project create "${PROJECTS[$i]}"

    incus project set "${PROJECTS[$i]}" \
        limits.cpu="${RESOURCES_CPU_PER_PROJECT[$i]}" \
        limits.memory="${RESOURCES_MEMORY_PER_PROJECT[$i]}"
done


