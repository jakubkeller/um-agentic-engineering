#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

profileName=${1:-""}

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

# Infra
echo
echo "** Deploying Infra **"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"


## Deploy
if [ -z $profileName ]; then
    echo "CI/CD Pipeline - No Profile Name"    
    source $LOCAL_PATH/scripts/cicd/setenv.sh
else
    echo "Local Development - Profile $profileName Specified"
fi

for file in $(find $LOCAL_PATH/infra/src/** -name *Stack.cs); do
(
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    stackName=$(basename $file .cs)
        
    echo
    echo "Deploying Stack: $stackName"
    echo

    cd $LOCAL_PATH/infra

    if [ -z $profileName ]; then
        cdkchk="npx cdk diff --fail $stackName"
        cdkdeploy="npx cdk deploy --ci --require-approval never $stackName"
    else
        cdkchk="npx cdk diff --fail --profile $profileName $stackName"
        cdkdeploy="npx cdk deploy --profile $profileName $stackName"
    fi

    # detect changes to the stack
    if $cdkchk; then
        echo "No changes detected for $stackName"
        echo "Deployment skipped for $stackName"
    else
        echo "Changes detected on $stackName"
        $cdkdeploy
        echo "CDK deploy executed for $stackName "
    fi
)
done
