#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

profileName=${1:-""}

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

# Infra
echo
echo "** Destroying Infra **"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"


## Deploy
if [ -z $profileName ]; then
    echo "CI/CD Pipeline - No Profile Name"
else
    echo "Local Development - Profile $profileName Specified"
fi



for file in $(find $LOCAL_PATH/infra/src/** -name *Stack.cs); do
(
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    stackName=$(basename $file .cs)
        
    echo
    echo "Destroying Stack: $stackName"
    echo

    source $LOCAL_PATH/scripts/cicd/setenv.sh

    cd $LOCAL_PATH/infra

    if [ -z $profileName ]; then
        npx cdk destroy --ci --force $stackName
    else
        npx cdk destroy --profile $profileName $stackName
    fi

)
done

echo "Deploy completed"
