#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

echo
echo "** Publishing App **"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "PUBLISH_PATH: $PUBLISH_PATH"
echo "CONFIGURATION: $CONFIGURATION"

# App
for projFile in $(find "$LOCAL_PATH/app/src" -name "*.csproj"); do
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    dirName=$(basename $(dirname "$projFile") .csproj)
    echo
    echo "Publishing Project: $dirName"
    echo    
    cd $(dirname $projFile)
    dotnet publish --configuration "$CONFIGURATION" --no-build --output "$PUBLISH_PATH/$dirName/" 
    echo "The "$dirName" was successfully published to "$PUBLISH_PATH/$dirName""
done
