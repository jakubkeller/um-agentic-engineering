#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
# set -exo pipefail
set -eo pipefail

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

# Infra
echo ""
echo "** Building and Testing Infra **"
echo ""
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "BUILD_PATH: $BUILD_PATH"

## Build
for projFile in $(find $LOCAL_PATH/infra/src -name *.csproj); do
(
    dirName=$(basename $(dirname $projFile))
    
    echo ""
    echo "Building Project: $dirName"
    echo ""

    
    cd $(dirname $projFile)
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi

    dotnet build -c Release -o $BUILD_PATH/$dirName/release/publish

    echo "The $dirName Application successfully built to $BUILD_PATH/$dirName/release/publish"
) 
done

echo "Build Success!!"
