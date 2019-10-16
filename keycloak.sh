#!/usr/bin/env bash
set -e

echo ">>Creating user"
if [ $KEYCLOAK_USER ] && [ $KEYCLOAK_ADMIN_PASSWORD ]; then
    $KEYCLOAK_DIR/bin/add-user-keycloak.sh --user $KEYCLOAK_USER --password $KEYCLOAK_ADMIN_PASSWORD
fi

# -Dkeycloak.hostname.fixed.httpPort=${PORT:-8080} 

# Todo: Maybe not needed anymore?
SYS_PROPS=" -Dkeycloak.hostname.fixed.alwaysHttps=false"


########################
# JGroups bind options #
########################

# Todo: Simply these lines of code. We can just always set the ip from 'hostname --all-ip-addresses'
# No need to do checks
if [ -z "$BIND" ]; then
    BIND=$(hostname --all-ip-addresses)
fi
if [ -z "$BIND_OPTS" ]; then
    for BIND_IP in $BIND
    do
        BIND_OPTS+=" -Djboss.bind.address=$BIND_IP -Djboss.bind.address.private=$BIND_IP "
    done
fi
SYS_PROPS+=" $BIND_OPTS"


##################################################
# Copy Keycloak SPI's to JBoss deployment folder #
##################################################

# A 'spi' directory is expected as part of the CF app being deployed
if [ -d "/home/vcap/app/spis" ]; then
    echo ">> Copying SPIs."
    # Delete existing JBoss 'deployments' directory. Then recreate the 'deployments' directory, but as
    # a symlink to CF app directory

    #rm -rf "$KEYCLOAK_DIR/standalone/deployments"
    #ln -s /home/vcap/app/spi "$KEYCLOAK_DIR/standalone/deployments"
    ls spis/*/target/libs/*.jar
    cp spis/*/target/libs/*.jar "$KEYCLOAK_DIR/standalone/deployments"
fi

########################
# Start JBoss/Keycloak #
########################

echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
exec $KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
exit $?
