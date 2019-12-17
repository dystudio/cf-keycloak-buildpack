#!/usr/bin/env bash
set -e

export BUILD_DIR=$(cd "$1/" && pwd)


##################################################
# Run Keycloak configuration scripts             #
##################################################
STARTUP_SCRIPTS_DIR=${STARTUP_SCRIPTS_ROOT}/startup-scripts

# Copy of autorun.sh script from the Keycloak docker image.
# This is what runs the startup-scripts for docker.
echo ">>Looking for startup scripts in ${STARTUP_SCRIPTS_DIR}"
# HAH the scripts are here yet, they will be copied over later on
# Altough how the realm creation works?!?
if [[ -d "$STARTUP_SCRIPTS_DIR" ]]; then
  # First run cli autoruns
  for f in "$STARTUP_SCRIPTS_DIR"/*; do
    if [[ "$f" == *.cli ]]; then
      echo "Executing cli script: $f"
      bin/jboss-cli.sh --file="$f"
    elif [[ -x "$f" ]]; then
      echo "Executing: $f"
      "$f"
    else
      echo "Ignoring file in $STARTUP_SCRIPTS_DIR (not *.cli or executable): $f"
    fi
  done
fi

echo ">>Creating user"
if [ $KEYCLOAK_USER ] && [ $KEYCLOAK_ADMIN_PASSWORD ] && [ $WILDFLY_ADMIN_USER ] && [ $WILDFLY_ADMIN_PASSWORD ]; then
    $KEYCLOAK_DIR/bin/add-user-keycloak.sh --user $KEYCLOAK_USER --password $KEYCLOAK_ADMIN_PASSWORD
    # Add user for the management console.
    $KEYCLOAK_DIR/bin/add-user.sh --user $WILDFLY_ADMIN_USER --password $WILDFLY_ADMIN_PASSWORD --group SuperUser
else
    echo "WARNING: You have not set any Keycloak or Wildfly admin user credentials, so you will not be able to log in as admin to either system."
fi

# Todo: Maybe not needed anymore?
SYS_PROPS=" -Dkeycloak.hostname.fixed.alwaysHttps=false"


########################
# JGroups bind options #
########################
BIND=$(hostname --all-ip-addresses)

for BIND_IP in $BIND
do
    BIND_OPTS+=" -Djboss.bind.address=$BIND_IP -Djboss.bind.address.private=$BIND_IP "
done

SYS_PROPS+=" $BIND_OPTS"


##################################################
# Copy Keycloak SPI's to JBoss deployment folder #
##################################################
# A 'spis' directory is expected as part of the CF app being deployed
if [ -d "/home/vcap/app/spis" ]; then
    echo ">> Copying SPIs."
    ls spis/*/target/libs/*.jar
    cp spis/*/target/libs/*.jar "${KEYCLOAK_DIR}/standalone/deployments"
fi


################################################
# Copy password blacklists to the right folder #
################################################
if [ -d "/home/vcap/app/keycloak-config/blacklist" ]; then
    echo ">> Copying password backlists."
    ls keycloak-config/blacklist
    cp -a keycloak-config/blacklist/. "${KEYCLOAK_DIR}/standalone/data/password-blacklists"
fi


#######################################################################################
# Start JBoss/Keycloak                                                                #
# By using this it's possible to load realms but it won't override the existing ones. #
#######################################################################################
if [ $KEYCLOAK_IMPORT ]; then
    IMPORT_CONFIG=" -Dkeycloak.import=${BUILD_DIR}/${KEYCLOAK_IMPORT}"
fi


echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
$KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS $IMPORT_CONFIG -b 0.0.0.0
