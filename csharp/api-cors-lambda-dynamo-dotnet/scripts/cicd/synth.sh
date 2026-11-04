#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
# set -exo pipefail
set -eo pipefail

profileName=${1:-""}

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

# Infra
echo
echo "** Synthing Infra **"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"

for file in $(find $LOCAL_PATH/infra/src/** -name *Stack.cs); do
(
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    stackName=$(basename $file .cs)
        
    echo
    echo "Deploying Stack: $stackName"
    echo

    cd $LOCAL_PATH/infra

    if [ -z $profileName ]; then
        echo "CI/CD Pipeline - No Profile Name"
        source $LOCAL_PATH/scripts/cicd/setenv.sh
        npx cdk synth $stackName -o $ARTIFACTSTAGING_PATH/cdksynth
    else
        echo "Local Development - Profile $profileName Specified"
        npx cdk synth $stackName
    fi
)
done

echo "cdk synth complete"
