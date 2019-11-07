#!/usr/bin/env bash
set -e

echo ">>Creating user"
if [ $KEYCLOAK_USER ] && [ $KEYCLOAK_ADMIN_PASSWORD ]; then
    $KEYCLOAK_DIR/bin/add-user-keycloak.sh --user $KEYCLOAK_USER --password $KEYCLOAK_ADMIN_PASSWORD
    # Add user for the management console.
    $KEYCLOAK_DIR/bin/add-user.sh --user $WILDFLY_ADMIN_USER --password $WILDFLY_ADMIN_PASSWORD --group SuperUser
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

#SYS_PROPS+=" -Djboss.bind.address.management=0.0.0.0"

##################################################
# Copy Keycloak SPI's to JBoss deployment folder #
##################################################

# A 'spis' directory is expected as part of the CF app being deployed
if [ -d "/home/vcap/app/spis" ]; then
    echo ">> Copying SPIs."
    ls spis/*/target/libs/*.jar
    cp spis/*/target/libs/*.jar "$KEYCLOAK_DIR/standalone/deployments"
fi

########################
# Start JBoss/Keycloak #
########################

echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
exec $KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
exit $?
