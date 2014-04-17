# WebLogic Foreign JMS Config

The **`weblogic-buildpack`** creates a WebLogic Server Domain using the configuration yaml files present under the **`.wls`** folder of the application.

Sample Web Application (WAR) structure

     ```
              META-INF/
              META-INF/MANIFEST.MF
              WEB-INF/
              WEB-INF/lib/
              WEB-INF/web.xml
              WEB-INF/weblogic.xml
              index.jsp
              .wls/
              .wls/foreignjms/
              .wls/foreignjms/foreignJmsConfig1.yml           <--------- Foreign JMS Config file
              .wls/jdbc/
              .wls/jdbc/jdbcDatasource1.yml
              .wls/jdbc/jdbcDatasource2.yml
              .wls/jms/
              .wls/jms/jmsConfig.yml
              .wls/jvm/
              .wls/jvm/jvmConfig.yml
              .wls/postJars/
              .wls/postJars/README.txt
              .wls/preJars/
              .wls/preJars/README.txt
              .wls/script/
              .wls/script/wlsDomainCreate.py                 <--------- WLST Script
              .wls/security/
              .wls/security/securityConfig.yml
              .wls/wlsDomainConfig.yml                       <--------- Domain Config file

       ```

The foreign jms config file under the **`.wls/foreignjms`** specify the foreign jms resources (other remote WLS JMS Services or non-WLS JMS resources) required in the server.
There can be multiple config files under the foreignjms folder.
Tweak the WLST Script if there is need for additional configuration changes.


Sample foreign jms config (from [foreignJmsConfig.yml](resources/wls/foreignjms/foreignJmsConfig.yml) )

```

# Configuration for the WebLogic Foreign JMS Services
---

# Each section deals with a subsystem
# Use '|' character to provide separation between Local and Remote JNDI Names
# Ordering is Local JNDI name | Remote JNDI Name
# Example:
#  destinations: jms/LocalQueueJNDIName|jms/RemoteQueueJNDIName
#  cfs: jms/cf/RemoteQXACF|jms/cf/LocalQXACF
#
# Use ';' character to provide multiple jms destinations or Connection Factories
# ex:
#  destinations: jms/LocalQueueJNDIName|jms/RemoteQueueJNDIName;jms/LocalTopicJNDIName|jms/RemoteTopicJNDIName
#  cfs: jms/cf/LocalQXACF|jms/cf/RemoteQXACF
#
# For jndi properties, use ';' as separator for various name-value pairs and '=' to denote the name/value.
# Ensure the javax.naming... keys and values are correct
# For example:
#    javax.naming.factory.initial=Initial_Context_Factory (can be jndi/ldap/fs context..)
#    javax.naming.provider.url=REMOTE_URL_ENDPOINT or bindings file
#    javax.naming.security.principal=USERNAME
#    javax.naming.security.credentials=PASSWORD
#
#

ForeignJMS-1:
  name: TestForeignJms
  #Provide all the related jndi connection, properties info.. under properties rather than individual entries
  jndiProperties: javax.naming.factory.initial=weblogic.jndi.WLInitialContextFactory;javax.naming.provider.url=t3://remoteHost:7001;javax.naming.security.principal=weblogic;javax.naming.security.credentials=weblogic
  destinations: jms/LocalQueueJNDIName|jms/RemoteQueueJNDIName;jms/LocalTopicJNDIName|jms/RemoteTopicJNDIName
  cfs: jms/cf/LocalQXACF|jms/cf/RemoteQXACF;jms/cf/LocalTXACF|jms/cf/RemoteTXACF


```

* **`name`** would determine the JMS Module and Foreign JMS Server configuration
* Provide all the Javax Naming parameters (like provider url, credentials, initial context factory) to connect to the remote servie provider using the **`jndiProperties`** parameter. Use the **`=`** to specify the name-value pairs.
* Specify the remote Connection Factories using **`cfs`** parameter.
* Specify the Destinations using **`destinations`** parameter.
* Use  **`|`** as separator between the local jndi (jndi name for the local stub of the remote service) and remote jndi name (actual JNDI name of the remote service) for both destinations and connection factories.
  Syntax: Local_JNDI_Name|Remote_JNDI_Name

  Sample:
  ```
    cfs: jms/cf/LocalQXACF|jms/cf/RemoteQXACF;jms/cf/LocalTXACF|jms/cf/RemoteTXACF
  ```
* Use **`;`** to separate multiple destinations or connection factories.



