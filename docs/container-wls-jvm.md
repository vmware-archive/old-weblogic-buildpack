# WebLogic JVM Config

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
              .wls/jms/jmsConfig.yml
              .wls/jvm/
              **.wls/jvm/jvmConfig.yml                         <--------- JVM Config file**
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

The jvm config file under the **`.wls/jvm`** can be used to specify the min and max heap and Permanent generation sizes for the jvm of WebLogic Server.
Additionally, it can also specify other command line or jvm options like verbose:gc, PrintGCTimestamps etc to be passed to the JVM arguments.
These will be used during the start of the server.

The buildpack would use some defaults (128M for Perm Gen, min of 512m and max of 1024m for heap) in the absence of the jvmConfig file.
All parameters for heap and perm specified are in MB.

Sample domain config (from [jvmConfig.yml](resources/wls/jvm/jvmConfig.yml)
```

# Configuration for the WebLogic Server JVM
---

# All JVM parameters specified default to MB
JVM:
  # For optimal performance, set min and max perm size to same value
  # for large apps with lots of classes/jsp etc., bump to 512 or 1024m
  minPerm: 256
  maxPerm: 256
  #maxPerm: 512
  # For optimal perf, set min and max heap size to same value
  # For large apps, bump to 1024 or 2048 MB (depending on the quota..)
  minHeap: 512
  maxHeap: 1024
  otherJvmOpts: -verbose:gc -Xloggc:gc.log -XX:+PrintGCDetails -XX:+PrintGCTimeStamps  -XX:+HeapDumpOnOutOfMemoryError


```
* **`minPerm`** denotes initial size of Perm Generation space
* **`maxPerm`** denotes maximum size of Perm Generation space
* **`minHeap`** denotes minimum size of Java Heap
* **`maxHeap`** denotes maximum size of Java Heap
* **`otherJvmOpts`** can be used to specify additional command line arguments or JVM settings.


