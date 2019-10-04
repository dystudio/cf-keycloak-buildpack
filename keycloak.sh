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

echo ">>Executing standalone.sh -c=standalone-ha.xml $SYS_PROPS $@"
exec $KEYCLOAK_DIR/bin/standalone.sh -c=standalone-ha.xml $SYS_PROPS -b 0.0.0.0
exit $?
