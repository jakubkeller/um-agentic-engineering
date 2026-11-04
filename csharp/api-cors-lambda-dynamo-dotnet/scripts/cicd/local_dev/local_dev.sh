#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

# Enable glob patterns - Required for bash to interpret patterns like /**/*.csproj
shopt -s globstar

profileName="pod0-admin"
#export ENVIRONMENTTYPE="sandbox"

# Set path variables
FULL_PATH=$(readlink -f "$0")
export LOCAL_SCRIPTS_PATH="$(dirname $FULL_PATH)"
export SCRIPTS_PATH="$(dirname $LOCAL_SCRIPTS_PATH)"
export LOCAL_PATH="$( dirname $(dirname $SCRIPTS_PATH))"
export BUILD_PATH="$LOCAL_PATH/dist"
export PUBLISH_PATH="$LOCAL_PATH/dist/release/publish"
export TEST_RESULT_PATH="$LOCAL_PATH/dist/tests"
export ARTIFACT_STAGING_PATH="$LOCAL_PATH/dist/stage"
export CODECOVERAGE_SETTINGS_PATH="$LOCAL_PATH/app/test/**"
export CONFIGURATION="Release"

# Set tool versions
export NODE_VERSION="22.14.0"
export CDK_VERSION="2.1005.0"
export PYTHON_VERSION=""

# Make directories for output
mkdir -p $PUBLISH_PATH
mkdir -p $ARTIFACT_STAGING_PATH
mkdir -p $TEST_RESULT_PATH

# Ensure shell scripts are executable
chmod +x $SCRIPTS_PATH/*.sh
chmod +x $LOCAL_SCRIPTS_PATH/*.sh

cd $LOCAL_PATH

if [ -n "$NODE_VERSION" ]; then   
    echo "Setting nvm to use $NODE_VERSION"
    source ~/bin/nvm/nvm.sh
    nvm use --silent $NODE_VERSION || nvm install $NODE_VERSION --latest-npm
else #We will load latest version of node by default
    echo "Use latest version of node"
    source ~/bin/nvm/nvm.sh
    nvm use --silent --lts || nvm install --lts --latest-npm
fi

if [ -n "$CDK_VERSION" ]; then
    echo "Installing aws-cdk $CDK_VERSION"
    npm install aws-cdk@$CDK_VERSION
else
    echo "Installing latest version of aws-cdk"
    npm install --location=global aws-cdk
fi

if [ -n "$PYTHON_VERSION" ]; then
    echo "Setting pyenv to set use python $PYTHON_VERSION for all directories under $(pwd)"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
    pyenv local $PYTHON_VERSION 2>&- || eval "pyenv install -s $PYTHON_VERSION; pyenv local $PYTHON_VERSION"
    python -m pip install --upgrade pip setuptools virtualenv wheel
    python -m virtualenv .venv
fi

# Build the app and infrastructure
$LOCAL_SCRIPTS_PATH/build.sh
echo
read -p "Build Complete. Press enter to resume ..."

# # Test
$LOCAL_SCRIPTS_PATH/tests.sh
echo
read -p "Test Complete. Press enter to resume ..."

# # Publish 
$LOCAL_SCRIPTS_PATH/publish_app.sh
echo
read -p "Publish Complete. Press enter to resume ..."

# # Login
# #aws sso login --profile $profileName
# #read -p "Login Complete. Press enter to resume ..."

# # Synth
$SCRIPTS_PATH/synth.sh $profileName
echo
read -p "Synth Complete. Press enter to resume ..."

# # Login
aws sso login --profile $profileName
read -p "Login Complete. Press enter to resume ..."

# Deploy
$SCRIPTS_PATH/deploy.sh $profileName
echo
echo "Deploy Complete."