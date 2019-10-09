# Keycloak buildpack for CF

Keycloak is an open source software product to allow single sign-on with
Identity Management and Access Management aimed at modern applications and
services. 

This is a buildpack focused on get Keycloak running on CF (single and multi-instance)
suporting clustering via a external database and the discovery options provided
by the JGroups toolkit (http://jgroups.org)

## About this guide

This guide was not meant to repeat the official documentation. The first motivation
is offering a digested (and alternative) version based on EE experiences. The
idea is documenting an introduction to CloudFoundry buildpacks philosophy, in
order to offer context enough to understand how they work in CF and how
to maintain it.

The community offers other tools and toolkits to build custom buildpacks,
but the lack of documentation makes them difficult to start using it, specially
taking into consideration the simplicity of the design of CF buildpack interface.

Be aware, this document is not focused on advanced concepts, some of the
explanations are true enough to get the idea but probably not 100% correct once
one goes deep in the topic.


### Resources

You can find the official documentation about CF buildpack in https://docs.cloudfoundry.org/buildpacks/
There are other resources useful to get extra information and examples of CF
buildpacks in https://github.com/cloudfoundry-community/cf-docs-contrib/wiki/Buildpacks#community-created

* Creating custom buildpacks: https://docs.cloudfoundry.org/buildpacks/custom.html
* Buildpack packager tool: https://github.com/cloudfoundry/libbuildpack/tree/master/packager
* Library to create buildpacks: https://github.com/cloudfoundry/libbuildpack
* Buildpack interface definition: https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html


# CloudFoundry Buildpacks

A buildpack is a layer in between the stack and the application running in CF
Diego container. Each buildpack is in charge of providing dependencies like 
language frameworks and libraries in order to get applications running in a
container, that is the reason there are different buildpacks depending on the
type of application, e. g: Ruby on rails application uses `ruby_buildpack`, 
Python flask application uses `python_buildpack`, scala application uses
`java_buildpack`, ...

More than one buildpack is allowed in CF, but such buildpack(s)
need to support the multi-buildpack specification in other to get all working
together, but most of the applications only use one buildpack.


## A picture with some little brush-strokes and docker

In order to create a filesystem where an application runs on a Diego container,
we talk about 3 different parts, from bottom to top:

1. **The stack**. This is the base layer and provides a set of libraries and
utilities in order to get processess running in a container. It provides basic
tools like: bash, grep, cat, libopenssl, libc, ... The current supported stack
is based on Ubuntu 18.04 and it is called *cflinuxfs3*, previously cflinuxfs2
was based on ubuntu 14.04 (now is deprecated). For people familiar with Docker
containers this is quite similar to the instruction `FROM ubuntu:18.04` in 
a *Dockerfile*, but take into account that in cflinuxfs3 is not allowed to run
`apt` commands!

2. **Buildpack(s)**. So once there is a stack based on Ubuntu and my application
is built with Python Flask how I can install python?. The answer is by using
a buildpack. Ideally in a Dockerfile the next instructions would be `apt-get -y
install python python-flask` with all the rest of dependencies of Python and
Flask, but in CF there is no way for such workflow, `apt` is capped. A buildpack
is a set of commands and packages that Diego executes on top of the cfinuxfs3
stack to get all the external runtime dependencies of the application ready.
Those commands are defined according to an interface in order to: first, detect
if the application is suitable for the buildpack; second, get all resurces and
dependencies needed for the application; third, prepare and build the
dependencies by compiling them or moving to the proper location; finally,
tell CF how to run the entire stack (let's say is the `entrypoint` instruction
in a Dockerfile)

3. **Aplication bits**. This is what `cf push` takes from the current folder
(by default) and puts in the path `/home/vcap/app` inside the container.
In the docker world is like performing a `COPY` from the current folder to
`/home/vcap/app`


### From Docker to CF Diego containers

This is a table comparing Docker and CF Diego containers, taken from the
perspective of going from a `dockerfile` in order to build and get running a
fictitious Python application:

```
+================================================+===============================+=======================================================================+
|                        Dockerfile              |         CF (manifest)         |                                Notes                                  |
+================================================+===============================+=======================================================================+
| FROM ubuntu:18.04 as cflinuxfs3                | stack: cflinuxfs3             | In CF Diego, cflinuxfs3 (Ubuntu 18.04) is automatically provided when |
|                                                |                               | when the container is created, there is no need of importing anything.|
+------------------------------------------------+                               +-----------------------------------------------------------------------|
| RUN mkdir -p /home/vcap/app                    |                               | By running `cf push`, CloudFoundry copies the contents of the         |
| WORKDIR /home/vcap/app                         |                               | application (current folder) to `/home/vcap/app` within the container.|
| COPY . /home/vcap/app                          |                               |                                                                       |
+------------------------------------------------+-------------------------------+-----------------------------------------------------------------------+
| ENV DB_URI Server=s;Database=db;Uid=u;Pwd=p;   | env:                          | Environment variables are defined in the manifest.                    |
|                                                |   DB_URI: "Server=s;Data ..." |                                                                       |
+------------------------------------------------+-------------------------------+-----------------------------------------------------------------------+
| RUN apt-get update -y && \                     | buildpacks:                   | When CF uses a buildpack, after `cf push` and  before the application |
|   apt-get install -y python-pip python-dev     | - python_buildpack            | gets up and running -in the stating phase- goes through 4 steps:      |
|                                                |                               | 1. Detect: check if this buildpack is suitable to run the application |
|                                                |                               |    (no Docker equivalent).                                            |
|                                                |                               | 2. Supply: Get or download runtime dependencies for the aplication.   |
+------------------------------------------------+                               +-----------------------------------------------------------------------+
| COPY ./requirements.txt \                      |                               | 3. Finalize: prepares (compiles) the dependencies in order to get     |
|   /home/vcap/app/requirements.txt              |                               |    everything ready to run the app                                    |
| RUN pip install -r requirements.txt            |                               |                                                                       |
+------------------------------------------------+                               +-----------------------------------------------------------------------+
| ENTRYPOINT [ "python" ]                        | command: python app.py        | 4. Release: It defines how the application must be launched, the start|
| CMD [ "app.py" ]                               |                               |    process. Sometimes in CF, it is possible to define a `procfile`    |
|                                                |                               |    to tell Diego how to start the app, or by using the `-c` command   |
|                                                |                               |    line parameter with `cf push`                                      |
+------------------------------------------------+-------------------------------+-----------------------------------------------------------------------+
| EXPOSE 8080/tcp                                | health-check-type: http       | When the CF starts, CF Diego automatically defines this health-check  |
| HEALTHCHECK --interval=30s --timeout=1s \      | health-check-http-endpoint: / |                                                                       |
|   CMD curl -f http://localhost:8080/ || exit 1 |                               |                                                                       |
+------------------------------------------------+-------------------------------+-----------------------------------------------------------------------+
```

Points `1`, `2`, `3` and `4` of the CF buildpack are explained below in the next section.


# Cloudfoundry buildpack interface

As described in https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html,
the CF buildpack interface is really simple: 4 scripts/programs being executed
in order (each one represents a phase) in the staging process.

In Cloud Foundry, applications go through a staging phase before they get up and
running. For this staging phase, CF spin ups a temporary container and executes
the buildpack scripts to get all runtime dependencies and compiles the application.
If the process finishes successfully, CF creates an artifact called **droplet**
and stores it internally. The droplet contains everything to get the application
running on Diego container, when the application gets running in a container,
looks like this diagram:


```
+-[CF Diego container]-----------------||------------------------------------+
|                                      ||                                    |
|                   [Gorouter proxying requests to the app]                  |
|                                      ||                                    |
|                                      \/                                    |
|                                   +------+<----------------------+         |
|                      +-[Process]--+ 8080 +-------------+         |         |
|            +------+  |            +------+             |         |         |
| +-[Process]+ 2222 ++ |                                 |         |         |
| |          +------+| | Entrypoint of the application.  |         |         |
| | SSH daemon to    | | Process serving web application | +-[Process]----+  |
| | support`cf ssh`  | | on $PORT (default port is 8080).| |              |  |
| +------------------+ +---------------------------------+ | health-check |  |
|                                                          |              |  |
|                                                          +--------------+  |
|                                                                            |
| +-[Filesystem (droplet)]-------------------------------------------------+ |
| |                                                                        | |
| | +=[Application]=======================================================+| |
| | |                                                                     || |
| | |    (code/binaries in folder where `cf push` is done)                || |
| | |                                                                     || |
| | +=================+===================================================+| |
| |                   |                 Buildpack final                   || |
| |  Buildpacks pile  |  (last/unique buildpack defined in manifest.yml)  || |
| |  defined in the   +===================================================+| |
| |  cf manifest.yml  |                 Buildpack n-1                     || |
| |  only one is      |     (optional intermediate buildpack )            || |
| |  needed, it will  +===================================================+| |
| |  be the final     |                 Buildpack 1                       || |
| |                   |   (optional, first buildpack of the list)         || |
| | +=[stack]=========+===================================================+| |
| | | cflinuxfs3: Base set of libraries and utilities provided by CF in a || |
| | | Diego container, based on Ubuntu 18.04: bash, openssl libs, tar, ...|| |
| | +=====================================================================+| |
| +------------------------------------------------------------------------+ |
+----------------------------------------------------------------------------+
```

The last step of deploying an application in CF is about generating as many
containers as the user has defined in the manifest or in the command line,
copy the droplet to each container and execute the entrypoint to get the
application running and eventually, if one container crashes, CF will
recreate it (after a few tries) in a different cell (worker VM running
containers).


## Staging process

The process is explained here: https://docs.cloudfoundry.org/buildpacks/understand-buildpacks.html#buildpack-scripts

Given this section of a CF `manifest.yml` file:
```
  stack: cflinuxfs3
  buildpacks:
  - https://github.com/springernature/cf-keycloak-buildpack.git
```

After `cf push`, CF will create a temporary stating container with `cflinuxfs3`
stack already deployed and "it will take" the buildpack repository 
`https://github.com/springernature/cf-keycloak-buildpack.git` in a temporary
folder (`/tmp/$random`) and look for the `/bin` folder to execute in order:

  1. `bin/detect`. If the program exits successfully (`0` return code), the
  buildpack will be used with the application. If the exit code is not 0, the
  buildpack will be skipped, so no more actions with this buildpack.
  2. `bin/supply`. Gets or downloads all dependencies to run the application.
  All output sent to STDOUT is relayed to the user when they perform `cf push`.
  Also, this script receives these parameters:
  ```
     build_path = ARGV[0]  # App folder. Once the app is built is `/home/vcap/app`.
     cache_path = ARGV[1]  # Cache folder to store artifacts, provided by CF. 
     deps_path = ARGV[2]   # Dependencies folder. When app running is `/home/vcap/deps`
     index = ARGV[3]       # Index of the current buildpack in the list of builpacks.
  ```
  1. `bin/finalize`. Prepares the app for launch and runs only for the last buildpack.
  You can see it as the step which does the compilation and integration
  of the dependencies. It can make use of the cache folder to get/put assets from
  the `supply` script. It receives the same parameters as `supply`.
  4. `bin/release`. It should write to stdout a YAML configuration to tell
  CF Diego how to start the application. It only receives one argument:
  `build_path = ARGV[0]` 

Notes:
* Those programs/scripts do not share environment variables, so one cannot
define an environment variable an expect get it back on the next one. 
* The cache folder is a location the buildpack can use to store assets
during the stating process and next time the application is built it can
take them from there instead of -for example- download again. The assets
are stored only after the staging was successfully completed.
* There are no root access there, programs like `sudo` or `su` or programs
wich perform kernel modifications are not allowed.


### Debugging tips

Because of not using the community libraries and packager program: https://github.com/cloudfoundry/libbuildpack
there is no easy way to debug the buildpack. But here we have some ideas:

  * Make use of the Docker image `cloudfoundry/cflinuxfs3` in order to get
an environment similar to do a Diego container. Within the container is
just about copying the app folder to `/home/vcap/app` and execute the
buildpack scripts in order.
  * In general, any application which runs on CF can define pre-start scripts
to perform actions or set environment variables just by placing a them in
`.profile.d` folder on the application folder. The same idea can be applied
in the buildpack to define environment variables which can be consumed later
by the application.


