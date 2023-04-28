#!/bin/bash

MASTER_NODE="master-node"

multipass delete $(multipass ls | awk 'BEGIN{ORS=" ";} { if ($1 ~ /^node-[1-9]$/) { a[++n] = $1 }} END { for (i = 1; i <= n; i++) print a[i] }')${MASTER_NODE}
multipass purge
