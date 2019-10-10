# Keycloak clustering

Keycloak uses a Java framework for clustering called JGroups: http://www.jgroups.org/

From the website: 

"JGroups is a toolkit for reliable messaging. It can be used 
to create clusters whose nodes can send messages to each other. [...]
The most powerful feature of JGroups is its flexible protocol stack, 
which allows developers to adapt it to exactly match their application
requirements and network characteristics. [...]"

So in order to solve issues with Keycloak clusters one has to understand how
this framework works. Keycloak is just an application which makes use of
this toolkit.

One of the use cases of JGroups is to maintain state that is replicated 
across a cluster. For example, state could be all the HTTP sessions in a 
web server. If those sessions are replicated across a cluster, then clients 
can access any server in the cluster after a server which hosted the client’s
session crashed, and the user sessions will still be available.


## JGroups overview

JGroups uses a *JChannel* as the main API to connect to a cluster, 
send and receive messages, and to register listeners that are called when
things (such as member joins) happen.

What is sent around are *Messages*, which contain a byte buffer (the payload),
plus the sender’s and receiver’s address. Addresses are subclasses of 
org.jgroups.Address, and **usually contain an IP address plus a port.**

**The list of instances in a cluster is called a View,** and every instance
contains exactly the same view.

Instances can only send or receive messages after they’ve joined a cluster.

In a JGroups cluster there is always a coordinator node.

Group communication uses the terms group and member. Members are part of a
group. In the more common terminology, a member is a node and a group is a
cluster. 

Initial membership discovery is used to determine the current coordinator, 
once a coordinator is found, the joiner sends a JOIN request to the coord.
Discovery also fetches information about members and adds it to its local caches.
This information includes the logical name, UUID and IP address/port of
each member. When discovery responses are received, the information in it
will be added to the local caches.


## JGroups resources

* Manual: http://www.jgroups.org/manual4/index.html
* Cloud based cluster discovery algorithm: https://github.com/belaban/JGroups/blob/master/doc/design/CloudBasedDiscovery.txt


# Keycloak on CF: JGroups implementation

Ggroups tries to use multicast by default to setup the cluster, multicast
is problematic protocol in Cloud environments like AWS, GCP and  PaaS
platforms like Kubernetes or Cloud Foundry (container based).

For those platforms there are alternative ways to perform a cluster
discovery mechanism, Ggroups supports a lot of different ways, as
an example:

* FILE_PING
* JDBC_PING
* RACKSPACE_PING
* S3_PING
* AWS_PING
* Native S3 PING
* GOOGLE_PING2
* DNS_PING
* KUBE_PING
* AZURE_PING

You can have a look at those protocols in http://www.jgroups.org/manual4/index.html#DiscoveryProtocols

Focusing on a implementation for CloudFoundry, there are 2 main options
(but not only these ones!): DNS_PING and JDBC_PING.

*Given that **DNS_PING** is not possible right now in our CF platform and making 
the most of the database already needed by Keycloak for its data, we have 
decided to focus on **JDBC_PING** for now.*

Groups discovery protocol is configured by using two environment variables:

* JGROUPS_DISCOVERY_PROTOCOL
* JGROUPS_DISCOVERY_PROPERTIES

### DNS_PING: http://www.jgroups.org/manual4/index.html#_dns_ping

It uses DNS `A` or `SRV` records to perform discovery. Basically the 
idea is about querying a (local) DNS server to get a list of `A` records
or a given domain name (keycloak application domain), such list of ips would be
the candidates for the cluster. For example, given an aplication with the domain
`keycloak.example.domain.springernature.com`, querying the dns gives this
result:

```
$ host keycloak.example.domain.springernature.com
keycloak.example.domain.springernature.com has address 10.255.169.200
keycloak.example.domain.springernature.com has address 10.255.49.7
keycloak.example.domain.springernature.com has address 10.255.49.77
```
which means the cluster will have 3 nodes. Those nodes start a unicast
communication between each other to elect a coordinator and create a proper
cluster.

Cloudfoundry has support for this type of clustering discovery protocol by using
internal routes to all running applications: https://docs.cloudfoundry.org/devguide/deploy-apps/routes-domains.html#internal-routes
These internal routes will be in a `.internal` domain.

*As on October 2019 we have not enabled internal routers in our CloudFoundry platforms.*


### JDBC_PING: http://www.jgroups.org/manual4/index.html#_jdbc_ping

JDBC_PING uses a database to store information about cluster nodes used for discovery.
All cluster nodes are supposed to be able to access the same database.

When a node starts, it queries information about existing members from the database,
determines the coordinator and then asks the coord to join the cluster. 
It also inserts information about itself into the table, so others can subsequently find it.

When a node P has crashed, the current coordinator removes P’s information from the DB.
However, if there is a network split, then this can be problematic, as crashed members 
cannot be told from partitioned-away members.

when the JDBC_PING protocol is used (defined in a java datasource), it automatically
creates a table `JGROUPSPING` in the `keycloak` database:

```
mysql> desc JGROUPSPING;
+--------------+-----------------+------+-----+---------+-------+
| Field        | Type            | Null | Key | Default | Extra |
+--------------+-----------------+------+-----+---------+-------+
| own_addr     | varchar(200)    | NO   | PRI | NULL    |       |
| cluster_name | varchar(200)    | NO   | PRI | NULL    |       |
| ping_data    | varbinary(5000) | YES  |     | NULL    |       |
+--------------+-----------------+------+-----+---------+-------+
3 rows in set (0.01 sec)
```

This table keeps updated with the members of the cluster, but because the field `ping_data`
contains binary data, it makes difficult to visualize the members, but inside
this field is possible to perceive (sometimes can be a bit difficult!) the name of
the container of each instance (in CloudFoundry is possible to see it
with `cf ssh <application> -i <index>` and run `hostname`). The number of records
of this tables has to be the same as the application instances.

```
mysql> select * from JGROUPSPING;
+--------------------------------------+--------------+-------------------------------------------------------------+
| own_addr                             | cluster_name | ping_data                                                   |
+--------------------------------------+--------------+-------------------------------------------------------------+
| 12a2f42b-3eb3-b230-dc25-dc137ec457bb | ejb          | �%�~�W���+>��0 6df4bc9b-0ecb-4d21-484b-60f6         |
| c07fc663-a41b-4d81-4390-607bgj56s34f | ejb          | �"O�Rtcmbls395-vmzx-k3s0-dg8k-7834 {�&&���            |
+--------------------------------------+--------------+-------------------------------------------------------------+
2 rows in set (0.01 sec)
```

`ping_data` is a serialized class of http://www.jgroups.org/javadoc/org/jgroups/protocols/PingData.html
and one of the binary attributes is the physical ip address of the node 
(not possible to see it in mysql client output example), this is the way
used by each member to discover the peers, join (using unicast) and choose
a cluster coordinator.


## JGroups on Cloud Foundry

The protocol type and its settings are set by using environment variables (type java datasource)
in the application manifest with are processed by the buildpack in `bin/finalize` script in order
to run `cli` jboss scripts to setup **JDBC_PING**

```
JGROUPS_DISCOVERY_PROTOCOL: JDBC_PING
JGROUPS_DISCOVERY_PROPERTIES: datasource_jndi_name="java:jboss/datasources/KeycloakDS"
```

There are some consideration to take into account in Cloud Foundry.

### Networking

JDBC_PING or DNS_PING protocols are only for an initial cluster discovery, once the
cluster is created, the view (list of live members) is maintained in the database
or by DNS.

JGroups uses unicast (one-to-one) connections to keep the cluster alive (http://www.jgroups.org/manual4/index.html#TCP):
elect coordinator, sync state, ..., in order to allow this communication, it
keeps a server thread listening on port 7600 (by default), if the instances 
-after knowing the list of the nodes (in this case from the database)- cannot
connect to each other, the cluster fails.

By default, in CloudFoundry, all containers (even the ones running instances of
the same application) are completely isolated, no communication is possible
unless a network policy is added: https://docs.cloudfoundry.org/devguide/deploy-apps/cf-networking.html#create-policies

```
cf add-network-policy <keycloak-app-name> --destination-app <keycloak-app-name> --protocol tcp --port 7600
```

After definining a network policy to open the port 7600, the instances
are capable of seeing each other and clustering works.


### Tips

CloudFoundry is a PaaS implementation designed to run 12 factor apps: https://www.12factor.net/
Clustering mechanism like JGroups require a bit of tuning in order to fit in PaaS,
mainly because of no multicast opions, automatically scaling up and down, no graceful
instance termination, etc.

With JDBC_PING, Jgroups runs a JVM hook to automatically cleanup the database
when a node is stopped, but if the node crashes, it does not have enough time
to perform the deletion of itself from the table JGROUPSPING, or the node
was the coordinator and it did not update the view, the database can contain
wrong data.

When a node P has crashed, the current coordinator removes P’s information from the DB.
However, if there is a network split, then this can be problematic, as crashed members
cannot be told from partitioned-away members.

From the official documentation http://www.jgroups.org/manual4/index.html#_jdbc_ping:

The re-insertion is governed by attributes **info_writer_max_writes_after_view** and
**info_writer_sleep_time**: the former defines the number of times re-insertion
should be done (in a timer task) after each view change and the latter is the
sleep time (in ms) between re-insertions.

The value of this is that dead members are removed from the DB (because they
cannot do re-insertion), but network splits are handled, too.

Another attribute **clear_table_on_view_change** governs how zombies are handled.
Zombies are table entries for members which crashed, but weren’t removed for some
reason. E.g. if we have a single member A and kill it (via kill -9), then it
won’t get removed from the table.

If **clear_table_on_view_change** is set to true, then the coordinator clears
the table after a view change (instead of only removing the crashed members),
and everybody re-inserts its own information. This attribute can be set to
true if automatic removal of zombies is desired. However, it is costly, 
therefore if no zombies ever occur (e.g. because processes are never killed
with kill -9), or zombies are removed by a system admin, then it should be 
set to false.


#### Additional configuraton

|             Problem description                      |                             Possible solution                                             |
|:-----------------------------------------------------|:------------------------------------------------------------------------------------------|
| The initialization SQL needs to be adjusted          | In this case, you might want to look at `initialize_sql` **JDBC_PING** property           |
| When Keycloak crashes, the database is not cleared   | Turn `remove_old_coords_on_view_change` property on                                       |
| When Keycloak crashes, the database is not cleared   | Also, when a cluster is not too large, you may turn `remove_all_data_on_view_change` on   |
| Sometimes, Keycloak doesn't write its data in the db | You may lower `info_writer_sleep_time` and `info_writer_max_writes_after_view` properties |


For example:

```
JGROUPS_DISCOVERY_PROPERTIES: datasource_jndi_name="java:jboss/datasources/KeycloakDS",remove_old_coords_on_view_change="true",remove_all_data_on_view_change="true"
```


### Extra resources

Optimizations for cloud based discovery stores: https://github.com/belaban/JGroups/blob/master/doc/design/CloudBasedDiscovery.txt

The previous document is focused on the implementation in Cloud resources with buckets (S3, GCP, ...) but it seems
these implementations are specializations (subclass using inheritance) of FILE_PING. JDBC_PING seems also a specialization
of FILE_PING, so most likely the algorithm to elect coordinator, deal with partitions, etc. is the same.
