#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
# set -exo pipefail
set -eo pipefail

profileName=${1:-""}

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

## Tests
echo ""
echo "** Running Tests **"
echo ""
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "TESTRESULT_PATH: $TESTRESULT_PATH"

if [ -z $profileName ]; then
    echo "CI/CD Pipeline - No Profile Name"
    source $LOCAL_PATH/scripts/cicd/setenv.sh
fi

for projFile in $(find $LOCAL_PATH/app/test -name *.sln); do
(
    dirName=$(basename $(dirname $projFile))
    
    echo ""
    echo "Testing Solution and Generating Code Coverage: $projfile"
    echo ""
    
    cd $(dirname $projFile)
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    dotnet test --logger "trx" --no-build --results-directory $TESTRESULT_PATH --settings $LOCAL_PATH/app/test/**/CodeCoverage.runsettings --collect "XPlat Code Coverage"
    echo "Solution Tested and results output to $TESTRESULT_PATH"
) 
done

echo "Test executed successfully."
