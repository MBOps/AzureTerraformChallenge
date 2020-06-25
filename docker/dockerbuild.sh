#!/bin/bash

while test $# -gt 0; do
  case $1 in
    -h|--help)
    echo
    echo "options:"
    echo "-h, --help                show help"
    echo "-c, --container-registry  container registry URL" 
    echo "-u, --user                container registry username" 
    echo "-p, --password            container registry password"
    echo "-r, --repo                Git Repo URL"
    echo
    exit 0
    ;;
    -c|--container-registry)
      shift
      if test $# -gt 0; then
        export REGURL=$1
      else
        echo "no container registry URL"
        exit 1
      fi
      shift
      ;;
    -u|--user)
      shift
      if test $# -gt 0; then
        export REGUSER=$1
      else
        echo "no username"
        exit 1
      fi
      shift
      ;;
    -p|--password)
      shift
      if test $# -gt 0; then
        export REGPASSWORD=$1
      else
        echo "no passwordd"
        exit 1
      fi
      shift
      ;;
    -r|--repo)
      shift
      if test $# -gt 0; then
        export REPOURL=$1
      else
        echo "no Git Repo URL"
        exit 1
      fi
      shift
      ;;
  esac
done

git clone $REPOURL
docker build ./AzureEats-Website/Source/Tailwind.Traders.Web -t $REGURL/azureeats/web
echo $REGPASSWORD | docker login $REGURL -u $REGUSER --password-stdin
docker push $REGURL/azureeats/web
