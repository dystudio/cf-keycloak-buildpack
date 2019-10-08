#!/usr/bin/env bash
set -e

echo ">>Creating user"
if [ $KEYCLOAK_USER ] && [ $KEYCLOAK_PASSWORD ]; then
    $KEYCLOAK_DIR/bin/add-user-keycloak.sh --user $KEYCLOAK_USER --password $KEYCLOAK_PASSWORD
fi
# -Dkeycloak.hostname.fixed.httpPort=${PORT:-8080} 
#SYS_PROPS=" -Djboss.bind.address=0.0.0.0 -Djboss.bind.address.private=0.0.0.0"
SYS_PROPS=" -Dkeycloak.hostname.fixed.alwaysHttps=false"

# if [ "$KEYCLOAK_ALWAYS_HTTPS" != "" ]; then
#     SYS_PROPS+=" -Dkeycloak.hostname.fixed.alwaysHttps=$KEYCLOAK_ALWAYS_HTTPS"
# fi


########################
# JGroups bind options #
########################

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
cp /home/vcap/app/spi/* "$KEYCLOAK_DIR/standalone/deployments/"

########################
# Start JBoss/Keycloak #
########################

echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
exec $KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
exit $?
