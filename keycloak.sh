#!/usr/bin/env bash
set -e

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
$KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
STANDALONE_RESULT=$?

if [ $STANDALONE_RESULT -eq 0 ]; then
    echo ">>Enabling metrics"
    export PATH=$PATH:$KEYCLOAK_DIR/../jdk/bin
    $KEYCLOAK_DIR/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user $KEYCLOAK_USER --password $KEYCLOAK_ADMIN_PASSWORD
    $KEYCLOAK_DIR/bin/kcadm.sh update events/config -s "eventsEnabled=true" -s "adminEventsEnabled=true" -s "eventsListeners+=metrics-listener"
fi

exit $STANDALONE_RESULT
