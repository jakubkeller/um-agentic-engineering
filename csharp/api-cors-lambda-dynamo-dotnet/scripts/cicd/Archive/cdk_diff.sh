#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
# set -exo pipefail
set -eo pipefail

profileName=${1:-""}

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

## diff
echo ""
echo "CDK Diff"
echo ""
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "ARTIFACTSTAGING_PATH: $ARTIFACTSTAGING_PATH"


cd $LOCAL_PATH/infra

if [ -z $profileName ]; then
    echo "CI/CD Pipeline - No Profile Name"
    source $LOCAL_PATH/scripts/cicd/setenv.sh
    npx cdk diff --no-color 2> $LOCAL_PATH/infra/diff.txt
else  
    echo "Local Development - Profile $profileName Specified"
    npx cdk diff --profile $profileName
fi

# Display output
echo "======================================="
echo "cdk diff command output"
echo "======================================="
cat $LOCAL_PATH/infra/diff.txt

# Copy output to artifact staging location
cp $LOCAL_PATH/infra/diff.txt $ARTIFACTSTAGING_PATH/CDKDiff
echo "cdk diff published to $ARTIFACTSTAGING_PATH/CDKDiff"

echo "cdk diff complete"
