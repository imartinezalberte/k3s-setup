#!/bin/bash

. ../lib/utils.sh

URL="https://download.docker.com/linux/static/stable/x86_64/"

actual_version=(0 0 0)
while read -r docker_file; do
  suffix=${docker_file##*.}
  readarray -d'.' -t versions <<< "${docker_file%.*}"

  for((i=0; i<${#versions[*]}; i++)); do
    versions[$i]=$(sed 's/0\([0-9]\)/\1/' <<< ${versions[i]})
  done

  i=0
  while [[ ${i} -lt ${#versions[@]} ]] && [[ ${versions[i]} -eq ${actual_version[i]} ]]; do
    ((i++))
  done

  if [[ ${versions[i]} -gt ${actual_version[i]} ]]; then
    actual_version=("${versions[@]}")
  fi

done < <(curl -fsSL $URL | grep -E '<a href="docker-[0-9]+' | cut -d'"' -f2 | cut -d'-' -f2)

docker_binary=docker-$(IFS=. ; echo "${versions[*]}")
docker_binary_url="${URL}${docker_binary}.${suffix:-tgz}"

display $GREEN "We are going to use the URL ${docker_binary_url}"

curl -fsSL $docker_binary_url --output "./${docker_binary}.${suffix:-tgz}" && \
  tar -xvzf ./${docker_binary}.${suffix:-tgz} && \
  sudo install -o root -g root -m 0755 docker/docker /usr/local/bin/docker && \
  rm -rf docker "${docker_binary}.${suffix:-tgz}" && docker version

