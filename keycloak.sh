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

# JGroups for cluster discovery
if [ $JGROUPS_DISCOVERY_PROTOCOL ]; then
    echo ">>Set JGroups Discovery"
    
    JGROUPS_DISCOVERY_PROPERTIES_PARSED=`echo $JGROUPS_DISCOVERY_PROPERTIES | sed "s/=/=>/g"`
    echo ">>>Setting JGroups discovery to $JGROUPS_DISCOVERY_PROTOCOL with properties $JGROUPS_DISCOVERY_PROPERTIES_PARSED"
    echo "set keycloak_jgroups_discovery_protocol=${JGROUPS_DISCOVERY_PROTOCOL}" >> "$KEYCLOAK_DIR/bin/.jbossclirc"
    echo "set keycloak_jgroups_discovery_protocol_properties=${JGROUPS_DISCOVERY_PROPERTIES_PARSED}" >> "$KEYCLOAK_DIR/bin/.jbossclirc"
    echo "set keycloak_jgroups_transport_stack=${JGROUPS_TRANSPORT_STACK:-tcp}" >> "$KEYCLOAK_DIR/bin/.jbossclirc"
    
    echo ">>>Run jboss-cli"
    #$KEYCLOAK_DIR/bin/jboss-cli.sh --file="/opt/jboss/tools/cli/jgroups/discovery/default.cli" >& /dev/null
    $KEYCLOAK_DIR/bin/jboss-cli.sh --file="/opt/jboss/tools/cli/jgroups/discovery/default.cli"
fi

echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
exec $KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
exit $?
