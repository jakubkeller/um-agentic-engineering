#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

## Tests
echo
echo "** Running Tests **"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "TEST_RESULT_PATH: $TEST_RESULT_PATH"
echo "CONFIGURATION: $CONFIGURATION"

for solution in $(find "$LOCAL_PATH/" -name "*.sln"); do
    solutionName=$(basename "$solution")
    echo
    echo "Testing Solution and Generating Code Coverage: "$solutionName""
    echo
    cd $(dirname "$solution")
    if [[ -f DO_NOT_AUTOTEST ]]; then exit 0; fi
    dotnet test --logger "trx" --no-build --results-directory $TEST_RESULT_PATH --settings $CODECOVERAGE_SETTINGS_PATH/CodeCoverage.runsettings --collect "XPlat Code Coverage"  --configuration $CONFIGURATION
    echo "Solution "$solutionName" tested and results output to "$TEST_RESULT_PATH""
done
