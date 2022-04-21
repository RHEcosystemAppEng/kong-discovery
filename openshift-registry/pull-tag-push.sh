#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

pull() {
    echo pull $1
    podman pull $1
}

tag() {
  image_name=$2/${1##*/}
  echo tag $1 to $image_name
  podman tag $1 $image_name
}

push() {
  image_name=$2/${1##*/}
  echo push $image_name
  podman push $image_name
}

while IFS="" read -r p || [ -n "$p" ]
do
  pull $p
  tag $p $2
  push $p $2
done < $1