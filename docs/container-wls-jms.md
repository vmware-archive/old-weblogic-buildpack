# WebLogic JMS Config

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
              .wls/foreignjms/foreignJmsConfig1.yml
              .wls/jdbc/
              .wls/jdbc/jdbcDatasource1.yml
              .wls/jdbc/jdbcDatasource2.yml
              .wls/jms/
              **.wls/jms/jmsConfig.yml                         <--------- JVM Config file**
              .wls/jvm/
              .wls/jvm/jvmConfig.yml
              .wls/postJars/
              .wls/postJars/README.txt
              .wls/preJars/
              .wls/preJars/README.txt
              .wls/script/
              **.wls/script/wlsDomainCreate.py                 <--------- WLST Script**
              .wls/security/
              .wls/security/securityConfig.yml
              **.wls/wlsDomainConfig.yml                       <--------- Domain Config file**

       ```

The jms config file under the **`.wls/jms`** specify the jms resources required in the server.
Only non-persistent messaging is supported at this time as there is no support for persistent disks available across instance starts and also a new instance would get created each time by Cloud Foundry's DEA.
There can be multiple config files under the jms each with its own jms server (all running on the same WebLogic Server instance) and hosting a jms module with its own set of Destinations and CFs.
Tweak the WLST Script if there is need for additional configuration changes.


Sample jms config (from [jmsConfig.yml](resources/wls/jms/jmsConfig.yml)

```

# Configuration for the WebLogic JMS Server
---

# Each section deals with a subsystem
# Use ; character to provide multiple entries as in queues, topics or cf entries
#  ex:   jms/queue/TestQ;com/test/FooQ
#


JMS-1:
  jmsServer: TestJmsServer-1
  moduleName: TestJmsMod-1
  queues: jms/queue/TestQ;com/test/FooQ
  topics: jms/topic/TestT;com/test/FooT
  xaCfs: jms/cf/QXACF;jms/cf/TXACF
  nonXaCfs: jms/cf/QCF;jms/cf/TCF


```

* **`jmsServer`** used to specify the name of the JMS Server.
* **`moduleName`** used to specify the name of the JMS Module targetted to the server.
* **`queues`** used to specify set of local JMS Queues. Provide the jndi name of the Queue. If multiple queues, separate names using **`;`** character.
* **`topics`** used to specify set of local JMS Topics. Provide the jndi name of the Topic. If multiple topics, separate names using **`;`** character.
* **`xaCfs`** used to specify set of JMS Connection Factories that are XA enabled. Provide the jndi name of the CFs. If multiple CFs, separate names using **`;`** character.
* **`nonXaCfs`** used to specify set of JMS Connection Factories that are not XA enabled. Provide the jndi name of the CFs. If multiple CFs, separate names using **`;`** character.



