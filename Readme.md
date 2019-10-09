# Keycloak application in CloudFoundry

This is a buildpack to run [Keycloak](https://www.keycloak.org) in
Cloud Foundry

You can find a test application example in `test-app` folder.

By default, the buildpack does not need any files to get Keycloak
up and running in Cloud Foundry, but CF refuses to push an 
"application" from an empty folder (the manifest does not count
as application bits!).

In order to get a single instance (Standalone Mode) of Keycloak up and running:

1. In an empty folder create an empty file: `touch hola.txt`
2. Create a `manifest.yml`
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
        KEYCLOAK_PASSWORD: admin
    ```
3. Run `cf push`


The buildpack has support to automatically deploy Service Provider Interfaces (SPI's)
just by creating a `spi` folder in the application root and move the jars into it.
When the application starts, WildFly will load the Keycloak extensions.

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
