#!/bin/bash
__heredoc__='''
Script to publish a new version of this library on PyPI

Args:
    # These environment variables must / should be set
    TWINE_USERNAME : username for pypi
    TWINE_PASSWORD : password for pypi
    USE_GPG : defaults to True

Requirements:
     twine

Notes:
    # NEW API TO UPLOAD TO PYPI
    # https://packaging.python.org/tutorials/distributing-packages/

Usage:
    cd <YOUR REPO>

    # Set your variables or load your secrets
    export TWINE_USERNAME=<pypi-username>
    export TWINE_PASSWORD=<pypi-password>

    source $(secret_loader.sh)

    # Interactive/Dry run
    ./publish.sh 

    # Non-Interactive run
    #./publish.sh yes
'''

check_variable(){
    KEY=$1
    VAL=${!KEY}
    echo "[DEBUG] CHECK VARIABLE: $KEY=\"$VAL\""
    if [[ "$VAL" == "" ]]; then
        echo "[ERROR] UNSET VARIABLE: $KEY=\"$VAL\""
        exit 1;
    fi
}

# Options
CURRENT_BRANCH=${CURRENT_BRANCH:=$(git branch | grep \* | cut -d ' ' -f2)}
DEPLOY_BRANCH=${DEPLOY_BRANCH:=release}
DEPLOY_REMOTE=${DEPLOY_REMOTE:=origin}
VERSION=$(python -c "import setup; print(setup.parse_version())")

check_variable CURRENT_BRANCH
check_variable DEPLOY_BRANCH
check_variable DEPLOY_REMOTE
check_variable VERSION || exit 1

TAG_AND_UPLOAD=${TAG_AND_UPLOAD:=$1}
TWINE_USERNAME=${TWINE_USERNAME:=""}
TWINE_PASSWORD=${TWINE_PASSWORD:=""}

USE_GPG=${USE_GPG:="True"}
GPG_EXECUTABLE=${GPG_EXECUTABLE:=gpg}

__note___='''
GPG_IDENTIFIER=Erotemic
KEYID=$(gpg --list-keys --keyid-format LONG "$GPG_IDENTIFIER" | head -n 2 | tail -n 1 | awk '{print $1}' | tail -c 9)
echo "KEYID = '$KEYID'"

# https://help.github.com/en/articles/signing-commits
git config --local commit.gpgsign true
# Note the GPG key needs to match the email
git config --local user.email $UserEmail
# Tell git which key to sign
git config --local user.signingkey $KEYID
git config --local -l

GPG_KEY=297D757
'''

GPG_KEYID=${GPG_KEYID:=$(git config --local user.signingkey)}


echo "
=== PYPI BUILDING SCRIPT ==
CURRENT_BRANCH='$CURRENT_BRANCH'
DEPLOY_BRANCH='$DEPLOY_BRANCH'
VERSION='$VERSION'
TWINE_USERNAME='$TWINE_USERNAME'
"


echo "
=== <BUILD WHEEL> ===
"
echo "LIVE BUILDING"
# Build wheel and source distribution
python setup.py bdist_wheel --universal
python setup.py sdist 

BDIST_WHEEL_PATH=$(ls dist/*-$VERSION-*.whl)
SDIST_PATH=$(dir dist/*-$VERSION*.tar.gz)
echo "
echo "VERSION='$VERSION'"
BDIST_WHEEL_PATH='$BDIST_WHEEL_PATH'
SDIST_PATH='$SDIST_PATH'
"

check_variable BDIST_WHEEL_PATH
check_variable SDIST_PATH 

echo "
=== <END BUILD WHEEL> ===
"

echo "
=== <GPG SIGN> ===
"
if [ "$USE_GPG" == "True" ]; then
    # https://stackoverflow.com/questions/45188811/how-to-gpg-sign-a-file-that-is-built-by-travis-ci
    # secure gpg --export-secret-keys > all.gpg

    # REQUIRES GPG >= 2.2
    check_variable GPG_KEYID

    OLD_SIGS=$(ls dist/*.asc)
    if [[ "$OLD_SIGS" == "" ]]; then
        echo "Removing old signatures"
        rm $OLD_SIGS
    else
        echo "dist dir is clearn"
    fi

    echo "Signing wheels"
    GPG_SIGN_CMD="$GPG_EXECUTABLE --batch --yes --detach-sign --armor --local-user $GPG_KEYID"
    $GPG_SIGN_CMD --output $BDIST_WHEEL_PATH.asc $BDIST_WHEEL_PATH
    $GPG_SIGN_CMD --output $SDIST_PATH.asc $SDIST_PATH

    echo "Checking wheels"
    twine check $BDIST_WHEEL_PATH.asc $BDIST_WHEEL_PATH
    twine check $SDIST_PATH.asc $SDIST_PATH

    echo "Verifying wheels"
    gpg --verify $BDIST_WHEEL_PATH.asc $BDIST_WHEEL_PATH 
    gpg --verify $SDIST_PATH.asc $SDIST_PATH 

    check_variable BDIST_WHEEL_PATH
    check_variable SDIST_PATH
else
    echo "USE_GPG=False, Skipping GPG sign"
fi
echo "
=== <END GPG SIGN> ===
"


# Verify that we want to publish
if [[ "$TAG_AND_UPLOAD" != "yes" ]]; then
    if [[ "$TAG_AND_UPLOAD" != "no" ]]; then
        read -p "Are you ready to publish version='$VERSION' on branch='$TRAVIS_BRANCH'? (input 'yes' to confirm)" ANS
        echo "ANS = $ANS"
        TAG_AND_UPLOAD="$ANS"
    else
        echo "Ready to publish VERSION='$VERSION' on branch='$TRAVIS_BRANCH'" 
    fi
else
    echo "Not ready to publish VERSION='$VERSION' on branch='$TRAVIS_BRANCH'" 
fi

if [[ "$TAG_AND_UPLOAD" == "yes" ]]; then

    check_variable TWINE_USERNAME
    check_variable TWINE_PASSWORD

    if [[ "$CURRENT_BRANCH" == "$DEPLOY_BRANCH" ]]; then
        echo "CURRENT_BRANCH = $CURRENT_BRANCH"
        git tag $VERSION -m "tarball tag $VERSION"
        git push --tags $DEPLOY_REMOTE $DEPLOY_BRANCH
        if [ "$USE_GPG" == "True" ]; then
            twine upload --username $TWINE_USERNAME --password=$TWINE_PASSWORD --sign $BDIST_WHEEL_PATH.asc $BDIST_WHEEL_PATH
            twine upload --username $TWINE_USERNAME --password=$TWINE_PASSWORD --sign $SDIST_PATH.asc $SDIST_PATH
        else
            twine upload --username $TWINE_USERNAME --password=$TWINE_PASSWORD $BDIST_WHEEL_PATH 
            twine upload --username $TWINE_USERNAME --password=$TWINE_PASSWORD $SDIST_PATH 
        fi
    else
        echo "CURRENT_BRANCH!=DEPLOY_BRANCH. skipping tag and upload"
        echo "ONLY ABLE TO PUBLISH ON DEPLOY CURRENT_BRANCH

        CURRENT_BRANCH = $CURRENT_BRANCH
        DEPLOY_BRANCH = $DEPLOY_BRANCH
        "
    fi
    echo " !!! FINISH: LIVE RUN !!!"
else  
    echo "... Skiping tag and upload"
    echo " !!! FINISH: DRY RUN !!!"
    echo "To do live run set TAG_AND_UPLOAD=yes"
fi

__notes__="""
Notes:
    # References: https://docs.travis-ci.com/user/deployment/pypi/

    source $(load_secrets.sh)
    travis encrypt TWINE_PASSWORD=$TWINE_PASSWORD  
    travis encrypt TWINE_USERNAME=$TWINE_USERNAME 
    source $(unload_secrets.sh)
"""
