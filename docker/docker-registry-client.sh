#!/bin/bash

DOCKER_REPOSITORY=${1:-"localhost:5000"}

# If you want to display all the repositories that are inside of it
curl http://${DOCKER_REPOSITORY}/v2/_catalog | jq .

# You need to use the accept header with the value of the manifest version that you desire
curl -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" http://${DOCKER_REPOSITORY}/v2/privateRepo/privateImage/manifests/Tag | jq .
