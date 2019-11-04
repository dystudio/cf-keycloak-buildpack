# Keycloak application in CloudFoundry

This is a buildpack to run [Keycloak](https://www.keycloak.org) in
Cloud Foundry

You can find a test application example in `test-app` folder.

By default, the buildpack does not need any files to get Keycloak
up and running in Cloud Foundry, but CF refuses to push an 
"application" from an empty folder (the manifest does not count
as application bits!).

In order to get a single instance (Standalone Mode) of Keycloak up and running:

1. In an empty folder create an empty file (random name): `touch hola.txt`
2. Create a basic `manifest.yml`
    ```
    ---
    applications:
    - name: keycloak
    memory: 1G
    instances: 1
    random-route: true
    stack: cflinuxfs3
    buildpacks:
    - https://github.com/springernature/cf-keycloak-buildpack.git
    env:
        KEYCLOAK_USER: admin
        KEYCLOAK_ADMIN_PASSWORD: admin
    ```
3. Run `cf push` to get the app running in a random route.


The buildpack has support to automatically deploy Service Provider Interfaces (SPI's,
*Keycloak extensions or plugins*). There needs to be a `spis` directory in the application root and the jars need to match this linux file pattern to be found: `spis/*/target/libs/*.jar`. When the application starts, WildFly will load these 
Keycloak plugins and they will be available in the application.

For extra documentation ...
* about Cloudfoundry Buildpacks, go to https://github.com/springernature/cf-keycloak-buildpack/blob/master/docs/buildpack-howto.md
* about Keycloak clustering, go to https://github.com/springernature/cf-keycloak-buildpack/blob/master/docs/keycloak-clustering.md


## Considerations

1. **Keycloak is built on top of the WildFly application server** and it’s sub-projects
like Infinispan (for caching) and Hibernate (for persistence). This guide only
covers basics for infrastructure-level configuration. It is highly recommended
that you peruse the documentation for WildFly and its sub projects: http://docs.wildfly.org/13/Admin_Guide.html
2. Keycloak comes with its own embedded Java-based relational database called H2. 
This is the default database that Keycloak will use to persist data and really
only exists so that you can run the authentication server out of the box. 
**It is highly recommended replace it with a more production ready external database**
3. Keycloak uses the following as data sources:
   * A database is used to persist permanent data, such as user information.
   * An Infinispan cache is used to cache persistent data from the database and
     also to save some short-lived and frequently-changing metadata, such as for
     user sessions. Infinispan is usually much faster than a database, however the
     data saved using Infinispan are not permanent and is not expected to persist
     across cluster restarts.
4. **Keycloak asumes that Proxy/LoadBalancers offer support for sticky sessions**, 
which means that the load balancer is able to always forward all HTTP requests
from the same user to the same Keycloak instance in same data center.
It is generally wise to configure your environment to use loadbalancer with
sticky sessions. It is beneficial for performance, please read:
https://www.keycloak.org/docs/7.0/server_installation/#sticky-sessions


## Optimizations

Because of previous considerations:

1. Most of the buildpack actions and procedures are WildFly configuration procedures:
   XML modules, SPI installation, etc . The buildpack is just an automated way of
   installing the application in a container, so it is convenient understanding
   the workflow of a manual installation first.
2. Take into account the amount of memory assigned to the application, because
   there are different kind of "memories" to consider. Also the amount of instances,
   and load (request/s coming to the application), memory consumption of the SPI modules,
   etc. Please, consider how much memory is assigned for:
   * Application instance memory
   * JVM memory settings
   * Infinispan memory settings (for caching)
3. CloudFoundry routing layer (GoRouters) is capable of performing sticky sessions
   by using **JSESSIONID** cookie: https://docs.cloudfoundry.org/concepts/http-routing.html#sessions
   and because of how Keycloak handles the sessions, this setting can
   offer big improvements, specially if the cluster is big and with a lot of load.
   Keycloak uses different cookie names, but it is possible to change the configuration
   to define the cookie name.

## Debugging

You can check the cluster view using `jboss-cli`:

```
cf ssh keycloak-poc
export PATH=$PATH:/home/vcap/deps/0/jdk/bin/:/home/vcap/deps/0/keycloak/bin/
jboss-cli.sh -c  '/subsystem=jgroups/channel=ee:read-attribute(name=view)'
```

The result should contains as many instances as you declare:

```
{
"outcome" => "success",
"result" => "[70d3d988-fb5a-4ceb-406c-6d04|1] (2) [70d3d988-fb5a-4ceb-406c-6d04, 14a493d4-3a48-4323-6287-7c56]"
}
```

In general you can use `jboss-cli` to perform actions and retrieve information:

```
boss-cli.sh
You are disconnected at the moment. Type 'connect' to connect to the server or 'help' for the list of supported commands.
[disconnected /] connect
[standalone@localhost:9990 /] help

SYNOPSIS

    help ( [<command or operation name>] | [--commands] ) 


DESCRIPTION

    Print the commands and operations help content.
    Use completion to discover commands and operations. Here are some of the
    most basic supported commands:
    
    cn (or cd)    - change the current node path to the argument.
    connect       - connect to the server or domain controller.
    deploy        - deploy an application.
    history       - print or disable/enable/clear the history expansion.
    ls            - list the contents of the node path.
    pwn (or pwd)  - prints the current working node.
    quit (or q)   - quit the command line interface.
    undeploy      - undeploy an application.
    version       - prints the version and environment information.

ALIASES

    h


OPTIONS

    --commands  - List of available commands. The resulting listing may depend
                  on the current context.E.g. some of the commands require an
                  established connection to the controller (standalone or
                  domain). These commands won't appear in the listing unless
                  the connection has been established. Other commands may
                  depend on the availability of specific subsystems. E.g. if
                  the messaging subsystem is not available, messaging-related
                  commands will not be listed.


ARGUMENT

    The command or operation name.



[standalone@localhost:9990 /] ls
core-service                               interface                                  system-property                            management-minor-version=0                 process-type=Server                        release-codename=                          schema-locations=[]                        
deployment                                 path                                       launch-type=STANDALONE                     name=eb41b601-74b8-41e6-4f24-aead          product-name=Keycloak                      release-version=8.0.0.Final                server-state=running                       
deployment-overlay                         socket-binding-group                       management-major-version=10                namespaces=[]                              product-version=6.0.1                      running-mode=NORMAL                        suspend-state=RUNNING                      
extension                                  subsystem                                  management-micro-version=0                 organization=undefined                     profile-name=undefined                     runtime-configuration-state=ok             uuid=b719a480-2745-48d0-9968-b0d4187be6ba  

[standalone@localhost:9990 /] version
JBoss Admin Command-line Interface
JBOSS_HOME: /home/vcap/deps/0/keycloak
Release: 8.0.0.Final
Product: Keycloak 6.0.1
JAVA_HOME: null
java.version: 11
java.vm.vendor: Oracle Corporation
java.vm.version: 11+28
os.name: Linux
os.version: 4.15.0-47-generic

[standalone@localhost:9990 /] help --commands
Commands available in the current context:
attachment                              connection-info                         deployment disable-all                  deployment-info                         history                                 patch info                              run-batch                               security enable-http-auth-management    try                                     
batch                                   data-source                             deployment enable                       deployment-overlay                      if                                      patch inspect                           security disable-http-auth-http-server  security enable-sasl-management         undeploy                                
cd                                      deploy                                  deployment enable-all                   echo                                    jdbc-driver-info                        pwd                                     security disable-http-auth-management   security enable-ssl-http-server         unset                                   
clear                                   deployment deploy-cli-archive           deployment info                         echo-dmr                                ls                                      quit                                    security disable-sasl-management        security enable-ssl-management          version                                 
command                                 deployment deploy-file                  deployment list                         for                                     module                                  read-attribute                          security disable-ssl-http-server        security reorder-sasl-management        xa-data-source                          
command-timeout                         deployment deploy-url                   deployment undeploy                     grep                                    patch apply                             read-operation                          security disable-ssl-management         set                                     
connect                                 deployment disable                      deployment undeploy-cli-archive         help                                    patch history                           reload                                  security enable-http-auth-http-server   shutdown                                
To read a description of a specific command execute 'help <command name>'.

[standalone@localhost:9990 /] deployment-info
NAME                RUNTIME-NAME        PERSISTENT ENABLED STATUS 
keycloak-server.war keycloak-server.war false      true    OK     
nature-theme.jar    nature-theme.jar    false      true    OK     

[standalone@localhost:9990 /] connection-info
Username               $local, granted role ["SuperUser"] 
Logged since           Thu Oct 10 14:08:20 UTC 2019       
Not an SSL connection.                                    

[standalone@localhost:9990 /] deployment list               
keycloak-server.war  nature-theme.jar     

[standalone@localhost:9990 /] deployment info 
NAME                RUNTIME-NAME        PERSISTENT ENABLED STATUS 
keycloak-server.war keycloak-server.war false      true    OK     
nature-theme.jar    nature-theme.jar    false      true    OK     

[standalone@localhost:9990 /] jdbc-driver-info
NAME SOURCE                 
h2   com.h2database.h2/main 

[standalone@localhost:9990 /] /subsystem=jgroups/channel=ee:read-attribute(name=view)
{
    "outcome" => "success",
    "result" => "[eb41b601-74b8-41e6-4f24-aead|0] (1) [eb41b601-74b8-41e6-4f24-aead]"
}

[standalone@localhost:9990 /] quit
```



## Development

Based on these resources:

* Official docker images: https://github.com/keycloak/keycloak-containers/tree/master/server
* Kubernetes helm chart: https://github.com/codecentric/helm-charts
* Getting Started Guide: https://www.keycloak.org/docs/latest/getting_started/index.html
* Server Installation and Configuration Guide: https://www.keycloak.org/docs/latest/server_installation/index.html
* WildFly Getting Started Guide: http://docs.wildfly.org/18/Getting_Started_Guide.html


## Author

Gerard Laan, Jose Riguera  
Engineering Enablement, Springer Nature
