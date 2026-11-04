#!/bin/bash
# For an overview of set command options see https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Navitus DevOps team does not recommend using -u as, in combination with -e it will cause references to optional parameters to fail the pipeline
set -eo pipefail

profileName=${1:-""}
if [ -n "$profileName" ]; then
    echo
    echo "setenv.sh should not be sourced for local development."
    echo "Instead, define all your variables in the local_dev.sh script"
    echo
    exit 1
fi

# Variables in ALLCAPS are environment variables defined within the vars/vars-[environment].yaml templates

echo
echo "setenv.sh"
echo
echo "Environment variables used:"
echo "================================"
echo "LOCAL_PATH: $LOCAL_PATH"
echo "NODE_VERSION: $NODE_VERSION"
echo "PYTHON_VERSION: $PYTHON_VERSION"
echo "CDK_VERSION: $CDK_VERSION"

if [ -n "$NODE_VERSION" ]; then
    echo "Setting nvm to use $NODE_VERSION"
    source ~/bin/nvm/nvm.sh
    nvm use --silent $NODE_VERSION || nvm install $NODE_VERSION --latest-npm
else #We will load latest version of node by default
    echo "Setting nvm to use latest version of node"
    source ~/bin/nvm/nvm.sh
    nvm use --silent --lts || nvm install --lts --latest-npm
fi

if [ -n "$CDK_VERSION" ]; then
    echo "Installing aws-cdk $CDK_VERSION"
    npm install aws-cdk@$CDK_VERSION
else
    echo "Installing latest version of aws-cdk"
    npm install --location=global aws-cdk #ensure latest version of aws-cdk is installed under version of node just set
fi
echo "aws cdk version being used: $(npx cdk --version)"

if [ -n "$PYTHON_VERSION" ]; then
    echo "Setting pyenv to set use python $PYTHON_VERSION for all directories under $(pwd)"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
    pyenv local $PYTHON_VERSION 2>&- || eval "pyenv install -s $PYTHON_VERSION; pyenv local $PYTHON_VERSION"
    python -m pip install --upgrade pip setuptools wheel
    python -m venv .venv
fi