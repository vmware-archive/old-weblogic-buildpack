# Cloud Foundry WebLogic Buildpack

The **`weblogic-buildpack`** is a [Cloud Foundry][] buildpack for running JVM-based web applications on [Oracle WebLogic Application Server][].  It is designed to run WebLogic-based web or ear applications with minimal configuration on CloudFoundry.
This buildpack is based on a fork of the [java-buildpack][].

A single server WebLogic Domain configuration with deployed application would be created by the buildpack. The complete bundle of the server and application bits would be used to create a droplet for execution within Cloud Foundry.

## Features

* Download and install Oracle WebLogic and JDK binaries from a user-configured location.

* Configure a single server default WebLogic Domain. Configuration of the domain and subsystems would be determined by the configuration bundled with the application or the buildpack.

* The JVM settings like memory, heap, gc logging can be configured on a per app basis without modifying the buildpack.

* JDBC Datasources and JMS services are supported with domain configuration options.

* WebLogic Server can be configured to run in limited footprint mode (no support for EJB, JMS, known as WLX mode) or in full mode.

* Standard domain configurations are supported and able to be overridden by the application or the buildpack.

* Scale of the application via ‘cf scale’, not through increasing number of managed servers in the domain.

* The Application can be a single WAR (Web Archive) or EAR (multiple war/jar modules bundled within one Enterprise Archive).

* Its possible to expose the WebLogic Admin Console as another application, all within the overall context of the CF application endpoint (like testapps.xip.io)

* JDBC Datasources will be dynamically created based on Cloud Foundry Services bound to the application.

* Option to bundle patches, drivers, dependencies into the server classpath as needed.

* CF machinery will monitor and automatically take care of restarts as needed, rather than relying on WebLogic Node Manager.

* Its possible to bundle different configurations (like heap or jdbc pool sizes etc) for various deployments (Dev, Test, Staging, Prod) and have complete control over the configuration that goes into the domain and or recreate the same domain every time.

## Requirements

* WebLogic Server and JDK Binaries
   * The WebLogic Server release bits and jdk binaries should be accessible for download from a user-defined server (can be internal or public facing) for the buildpack to create the necessary configurations along with the application bits.
     Download the [Linux 64 bit JRE][] version and [WebLogic Server][] generic version.

     For testing in a [bosh-lite][] environment, create a loopback alias on the machine so the download server hosting the binaries is accessible from the droplet container during staging.
   
     Sample script for Mac
	 
     ```#!/bin/sh
        ifconfig lo0 alias 12.1.1.1
     ```

   * Edit the repository_root of [oracle_jre.yml](config/oracle_jre.yml) to point to the location hosting the Oracle JRE binary.
   
     Sample **`repository_root`** for oracle_jre.yml (under weblogic-buildpack/config)
     
	  ```
       repository_root: "http://12.1.1.1:7777/fileserver/jdk"
	  ````

      The buildpack would look for an **`index.yml`** file at the specified **repository_root** for obtaining jdk related bits.
      The index.yml at the repository_root location should have a entry matching the jdk/jre version and the corresponding jdk binary file
     
      ```
        ---
          1.7.0_51: http://12.1.1.1:7777/fileserver/jdk/jre-7u51-linux-x64.tar.gz
       ```
       Ensure the JRE binary is available at the location indicated by the index.yml referred by the jre repository_root

   * Edit the repository_root of [weblogic.yml](config/weblogic.yml) to point to the server hosting the WebLogic binary.

     Sample **`repository_root`** for weblogic.yml (under weblogic-buildpack/config)

      ```
      version: 12.1.+
      repository_root: "http://12.1.1.1:7777/fileserver/wls"
      preferAppConfig: false

      ```

	  The buildpack would look for an **`index.yml`** file at the specified **repository_root** for obtaining WebLogic related bits.
	  The index.yml at the repository_root location should have a entry matching the WebLogic server version and the corresponding release bits

      ```
        ---
          12.1.2: http://12.1.1.1:7777/fileserver/wls/wls1212_dev.zip
      ```
      Ensure the WebLogic Server binary is available at the location indicated by the index.yml referred by the weblogic repository_root.

      If one has to use a different version (like 10.3.6), make the binaries available on the fileserver location and update the index.yml to include the version and binary location.
      Sample index.yml file content when the file server is hosting the binaries of both 10.3.6 and 12.1.2 versions:

      ```
        ---
          12.1.2: http://12.1.1.1:7777/fileserver/wls/wls1212_dev.zip
          10.3.6: http://12.1.1.1:7777/fileserver/wls/wls1036_dev.zip
      ```

      Update the weblogic.yml (under weblogic-buildpack/config) in buildpack to use the correct version.

      ```
      version: 10.3.6
      repository_root: "http://12.1.1.1:7777/fileserver/wls"
      ```

      Use **`10.3.+`** notation if the server should the latest version under the 10.3 series.
      So, if both 10.3.6 and 10.3.7 binaries are available, the buildpack will automatically choose 10.3.7 over 10.3.6.

      Similarly, update the oracle_jre.yml as needed to switch between versions (while also updating the index.yml to point to the other available versions of jdk).


* Cloud Foundry Release version and manifest update

   * The Cloud Foundry Cloud Controller (cc) Nginx Engine defaults to a max payload size of 256MB. This setting is governed by the **`client_max_body_size`** parameter in the cc and ccng related properties of the cf manifest file.
   
     ```
	 
     properties:
       ...
       cc:
         app_events:
           cutoff_age_in_days: 31
         ....
         bulk_api_password: bulk-password
         client_max_body_size: 256M
       ....
       ccng:
         app_events:
           cutoff_age_in_days: 31
         app_usage_events:
           cutoff_age_in_days: 31
         ....
         bulk_api_password: bulk-password
         client_max_body_size: 256M
     
	 ```
	 
     The Cloud Foundry DEA droplet containing a zip of the full WebLogic server, JDK/JRE binaries and app bits would exceed 520 MB in size. The *`client_max_body_size`* limit of *256M* would limit the droplet transfer to Cloud Controller and failure during staging.
     The *`client_max_body_size`* attribute within the cf-manifest file should be updated to allow *750MB (or higher)* depending on size of the application bits.

     Sample manifest with updated *client_max_body_size*:

     ```

     properties:
       ...
       cc:
         app_events:
           cutoff_age_in_days: 31
         ....
         bulk_api_password: bulk-password
         client_max_body_size: 756M
       ....
       ccng:
         app_events:
           cutoff_age_in_days: 31
         app_usage_events:
           cutoff_age_in_days: 31
         ....
         bulk_api_password: bulk-password
         client_max_body_size: 756M

	 ```

     * CF Releases prior to **`v157`** used to hardcode the *`client_max_body_size`* to *256M*. So, overriding it with the manifest entry will not work unless the bosh-lite or hosting environment has been updated to *`v158`* or higher Cloud Foundry release.

## Application configuration

The buildpack looks for the presence of a **`.wls`** folder within the app at the root level as part of the detect call to proceed further.
In the absence of the **`.wls`** folder, it will look for presence of weblogic*xml files to detect it as a WebLogic specific application.
Additional configurations and scripts packaged within the **`.wls`** folder would determine the resulting WebLogic Domain and services configuration generated by the buildpack.

The buildpack can override some of the configurations (jdbc/jms/..) while allowing only the app bundled domain config and jvm config to be used for droplet execution using **preferAppConfig** setting.
Please refer to [Overriding App Bundled Configuration](#overriding-app-bundled-configuration) section for more details.


   * Sample App structure

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
              .wls/jvm/jvmConfig.yml
              .wls/postJars/
              .wls/postJars/README.txt
              .wls/preJars/
              .wls/preJars/README.txt
              .wls/script/
              .wls/script/wlsDomainCreate.py
              .wls/security/
              .wls/security/securityConfig.yml
              .wls/wlsDomainConfig.yml

       ```

     Sample Enterprise Application (EAR) structure
     ```

              META-INF/
              META-INF/MANIFEST.MF
              META-INF/application.xml
              APP-INF/
              APP-INF/lib/
              APP-INF/classes
              webapp1.war
              webapp2.war
              .wls/
              .wls/foreignjms/
              .wls/foreignjms/foreignJmsConfig1.yml
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
              .wls/script/wlsDomainCreate.py
              .wls/security/
              .wls/security/securityConfig.yml
              .wls/wlsDomainConfig.yml

       ```

   * Domain configuration (Required)
   
     The **`.wls`** folder should contain a single yaml file that contains information about the target domain, server name, user credentials etc.
     There is a sample [Domain config ](resources/wls/wlsDomainConfig.yml) bundled within the buildpack that can be used as a template to modify/extend the resulting domain.
	 
	 Refer to [domain](docs/container-wls-domain.md) for more details.
	 
   * Scripts (Required)
   
     There can be a **`script`** folder within **`.wls`** with a WLST jython script, for generating the domain
     There is a sample [Domain creation script](resources/wls/script/wlsDomainCreate.py) bundled within the buildpack that can be used as a template to modify/extend the resulting domain.
     
	 Refer to [script](docs/container-wls-script.md) for more details.
	 
   * JVM related configuration (non-mandatory)
   
     There can be a **`jvm`** folder within **`.wls`** with a yaml file for JVM configuration to be applied to the server instance.
     There is a sample [JVM config](resources/wls/jvm/jvmConfig.yml) bundled within the buildpack that can be used as a template to modify/extend the resulting domain with additional datasources.
     
	 Refer to [jvm](docs/container-wls-jvm.md) for more details.
	 
   * JDBC Datasources related configuration (non-mandatory)
   
     There can be a **`jdbc`** folder within **`.wls`** with multiple yaml files, each containing configuration relating to datasources (single or multi-pool).
     There is a sample [JDBC config](resources/wls/jdbc/jdbcDatasource1.yml) bundled within the buildpack that can be used as a template to modify/extend the resulting domain with additional datasources.
     
	 Refer to [jdbc](docs/container-wls-jdbc.md) for more details.
	 
   * JMS Resources related configuration (non-mandatory)
   
     There can be a **`jms`** folder within **`.wls`** with a yaml file, containing configuration relating to jms resources
     There is a sample [JMS config](resources/wls/jms/jmsConfig.yml) bundled within the buildpack that can be used as a template to modify/extend the resulting domain with JMS Destinations/Connection Factories.
	 
	 Refer to [jms](docs/container-wls-jms.md) for more details.
     	 
   * Foreign JMS Resources related configuration (non-mandatory)
   
     There can be a **`foreignjms`** folder within **`.wls`** with a yaml file, containing configuration relating to Foreign jms resources
     There is a sample [Foreign JMS config](resources/wls/foreignjms/foreignJmsConfig.yml) bundled within the buildpack that can be used as a template to modify/extend the resulting domain with Foreign JMS Services.
     	 
	 Refer to [foreignjms](docs/container-wls-foreignjms.md) for more details.

   * Security Resources related configuration (non-mandatory)
   
     There can be a **security** folder within **.wls** with a yaml file, containing configuration relating to security configuration
     Add security related configurations as needed and update the domain creation script to use those configurations to modify/extend the resulting domain.
   	 
   * Pre and Post Jar folders (non-mandatory)
   
     The **`preJars`** folder within **`.wls`** can contain multiple jars or other resources, required to be loaded ahead of the WebLogic related jars. This can be useful for loading patches, debug jars, other resources that should override the bundled WebLogic jars.
   
     The **`postJars`** folder within **`.wls`** can contain multiple jars or other resources, required to be loaded after the WebLogic related jars. This can be useful for loading JDBC Drivers, Application dependencies or other resources as part of the server classpath.

   * Pre-existing Services bound to the Application
     * Services that are bound to the application via the Service Broker functionality would be used to configure and create related services in the WebLogic Domain.
       * The **VCAP_SERVICES** environment variable would be parsed to identify MySQL, PostGres or other services and create associated configurations in the resulting domain.
       * The services can be either from [Pivotal Web Services Marketplace][] or [User Provided Services][] (like internal databases or services managed by internal Administrators and user applications just connect to it).



## Usage

To use this buildpack specify the URI of the repository when pushing an application to Cloud Foundry:

```
cf push -b https://github.com/pivotal-cf/weblogic-buildpack <APP_NAME> -p <APP_BITS>
```

While working in sandbox env against Bosh-Lite, its also possible to use a modified version of the buildpack without github repository using the zip format of the buildpack.
**Note:** Use zip to create the buildpack (rather than jar) to ensure the detect, compile, release have execute permissions during the actual building of the app.

```
cf create-buildpack weblogic-buildpack weblogic-buildpack.zip 1 --enable
```

This would allow CF to use the weblogic-buildpack ahead fo the pre-packaged java-buildpack (that uses Tomcat as the default Application Server).

## CF App Push
A domain would be created based on the configurations and script passed with the app by the buildpack on `cf push` command.

The droplet containing the entire WebLogic install, domain and application bits would be get executed (with the app specified jvm settings and generated/configured services) by Cloud Foundry.
A single server instance would be started as part of the droplet execution. The WebLogic Listen Port of the server would be controlled by the warden container managing the droplet.

The application can be scaled up or down using cf scale command. This would trigger multiple copies of the same droplet (identical server configuration and application bits but different server listen ports) to be executing in parallel.

Note: Ensure `cf push` uses **`-m`** argument to specify a minimum process memory footprint of 1024 MB (1GB). Failure to do so will result in very small memory size for the droplet container and the jvm startup can fail.

Sample cf push: 

````
cf push wlsSampleApp -m 1024M -p wlsSampleApp.war
```

## Examples

Refer to [WlsSampleWar](resources/wls/WlsSampleApp.war), a sample web application packaged with sample configurations under the resources/wls folder of the buildpack.
There is also a sample ear file [WlsSampleApp.ear](resources/wls/WlsSampleApp.ear) under the same location.

## Buildpack Development and Testing
* There are 3 stages in the buildpack: **`detect`**, **`compile`** and **`release`**. These can be invoked manually for sandbox testing.
  * Explode or extract the webapp or artifact into a folder
  * Run the <weblogic-buildpack>/bin/detect <path-to-exploded-app>
    * This should report successful detection on locating the **`.wls`** at the root of the folder

    Sample output:
    ```

    $ weblogic-buildpack/bin/detect wlsSampleApp
    oracle-jre=1.7.0_51 weblogic-buildpack=https://github.com/pivotal-cf/weblogic-buildpack.git#b0d5b21 weblogic=12.1.2

    ```

  * Run the <weblogic-buildpack>/bin/**compile** <path-to-exploded-app> <tmp-folder>
    * This should start the download and configuring of the JDK, WebLogic server and the WLS Domain based on configurations provided.
    * If no temporary folder is provided as second argument during compile, it would report error.

     ```ERROR Compile failed with exception #<RuntimeError: Application cache directory is undefined> ```

    Sample output for successful run:

    ```

    $ weblogic-buildpack/bin/compile wlsSampleApp tmp1
    -----> WebLogic Buildpack source: https://github.com/pivotal-cf/weblogic-buildpack.git#2cf927f6632af73a5b4f55c591a3e3ce14f2378f
    -----> Downloading Oracle JRE 1.7.0_51 from http://12.1.1.1:7777/fileserver/jdk/jre-7u51-linux-x64.tar.gz (0.1s)
           Expanding Oracle JRE to .java-buildpack/oracle_jre "Got command tar xzf t1/http:%2F%2F12.1.1.1:7777%2Ffileserver%2Fjdk%2Fjre-7u51-linux-x64.tar.gz.cached -C /Users/sparameswaran/workspace/wlsSampleApp2/.java-buildpack/oracle_jre --strip 1 2>&1"
    (0.6s)
    -----> Downloading Weblogic 12.1.2 from http://12.1.1.1:7777/fileserver/wls/wls1212_dev.zip (0.8s)
    -----> Expanding WebLogic to .java-buildpack/weblogic
    (4.4s)
    -----> Configuring WebLogic under .java-buildpack/weblogic
           Warning!!! Running on Mac, cannot use linux java binaries downloaded earlier...!!
           Trying to find local java instance on Mac
           Warning!!! Using JAVA_HOME at /Library/Java/JavaVirtualMachines/jdk1.7.0_51.jdk/Contents/Home/jre/bin/..
    -----> Finished configuring WebLogic Domain under .java-buildpack/weblogic/domains/cfDomain
    (1m 34s)

    ```

  * Run the <weblogic-buildpack>/bin/**release** <path-to-exploded-app>
    * This should report the final JVM parameters and or other java options and as well as execution script that would be used for the Droplet execution.

    Sample output:

    ```

    $ weblogic-buildpack/bin/release wlsSampleApp
    ---
    addons: []
    config_vars: {}
    default_process_types:
      web: JAVA_HOME=$PWD/.java-buildpack/oracle_jre USER_MEM_ARGS="-Xms512m -Xmx1024m
        -XX:PermSize=128m -XX:MaxPermSize=256m  -verbose:gc -Xloggc:gc.log -XX:+PrintGCDetails
        -XX:+PrintGCTimeStamps  -Dweblogic.ListenPort=$PORT -XX:OnOutOfMemoryError=$PWD/.java-buildpack/oracle_jre/bin/killjava.sh"
        /bin/sh ./setupPathsAndEnv.sh; /Users/sparameswaran/workspace/wlsSampleApp/.java-buildpack/weblogic/domains/cfDomain/startWebLogic.sh

    ```

* The buildpack would log the status and progress during the various execution stages into the .java-buildpack.log folder underneath the exploded-app directory.
  This log can be quite useful to debugging any issues or changes.

* The complete JDK/JRE and WebLogic Server install as well as the domain would be created under the .java-buildpack folder of the exploded application.

  Structure of the App, JDK and WLS Domain

  ```

  Exploded WebApp Root
     |-META-INF
     |-WEB-INF
     |--lib
     |-.wls                       <----------- WLS configuration folder referred by weblogic-buildpack
     |--foreignjms
     |--jdbc
     |--jms
     |--jvm
     |--security
     |--script                    <----------- WLST python script goes here
     |-.java-buildpack.log        <----------- buildpack log file
     |-.java-buildpack            <----------- buildpack created folder
     |--oracle_jre                <----------- JRE install·
     |----bin
     |----lib
     |--weblogic                  <----------- WebLogic install
     |----domains
     |------cfDomain              <----------- WebLogic domain
     |--------app
     |----------ROOT              <----------- Root of App deployed to server
     |--------autodeploy
     |--------config
     |----wls12120                <----------- wl_home
     |------coherence
     |------logs
     |------oracle_common
     |------wlserver

  ```

## Running WLS with limited footprint 

The generated WebLogic server can be configured to run with a limited runtime footprint by avoiding certain subsystems like  EJB, JMS, JCA etc.  This option is controlled by the **startInWlxMode** flag within the weblogic-buildpack [config](docs/container-wls.md)

      ```
      version: 12.1.+
      repository_root: "http://12.1.1.1:7777/fileserver/wls"
      preferAppConfig: false
      startInWlxMode: false
      ```


Setting the **startInWlxMode** to true would disable the EJB, JMS and JCA layers and reducing the overall memory footprint required by WLS Server. This is ideal for running pure web applications that don't use EJBs or messaging.  If there are any EJBs or jms modules/destinations configured, the activation of the resources will result in errors at server startup.

Setting the **startInWlxMode** to false would allow the full blown server mode.

Please refer to the WebLogic server documentation on the [limited footprint][] option for more details.

## Overriding App Bundled Configuration

The **`preferAppConfig`** parameter specified inside the [weblogic.yml](config\weblogic.yml) config file of the buildpack controls whether the buildpack or application bundled config should be used for Domain creation.

The weblogic-buildpack can override the app bundled configuration for subsystems like jdbc, jms etc.
The script for generating the domain would be pulled from the buildpack configuration (under resources/wls/script).

But the name of the domain, server and user credentials would be pulled from Application bundled config files so each application can be named differently.
The jvm configuration would also be pulled from the app bundled config (for app specific memory requirements).


      ```
      version: 12.1.+
      repository_root: "http://12.1.1.1:7777/fileserver/wls"
      preferAppConfig: false

      ```

Setting the  **`preferAppConfig`** to **`true`** would imply the app bundled configs (under .wls of the App Root) would always be used for final domain creation.
Setting the parameter to **`false`** would imply the buildpack's configurations (under resources\wls\) have higher precedence over the app bundled configs and be used to configure the domain.
The Application supplied domain config and jvm config file would be used for names of the domain, server, user credentials and jvm memory and command line settings.

For users starting to experiment with the buildpack and still tweaking and reconfiguring the generated domain, **`preferAppConfig` should be enabled so they can experiment more easily**.
This would allow the app developer to quickly change/rebuild the domain to achieve the desired state rather than pushing changes to buildpack and redeploy the application also each time.

**On reaching the desired domain configuration state (Golden state), save the configurations and scripts into the buildpack and disable the `preferAppConfig` parameter when no further changes are allowed or necessary to the domain.
One can also modify the domain creation script to lock down or block access to the WebLogic Admin Console or override the domain passwords, once the desired domain configuration has been achieved.**

*Note:
 The Cloud Foundry services that are injected as part of the registered Service Bindings for the application would still be used to create related services during application deployment.
 The Domain Administrators are expected to use the Service Bindings to manage/control the services that are exposed to the application as it moves through various stages (Dev, Test, PreProd, Prod).

## Configuration and Extension

The buildpack supports configuration and extension through the use of Git repository forking.  The easiest way to accomplish this is to use [GitHub's forking functionality][] to create a copy of this repository.  Make the required configuration and extension changes in the copy of the repository.  Then specify the URL of the new repository when pushing Cloud Foundry applications.  If the modifications are generally applicable to the Cloud Foundry community, please submit a [pull request][] with the changes.

To learn how to configure various properties of the buildpack, follow the "Configuration" links below. More information on extending the buildpack is available [here](docs/extending.md).

## Limitations (as of April, 2014)

* CF release version should be equal or greater than v158 to allow overriding the client_max_body_size for droplets (the default is 256MB which is too small for WebLogic droplets).

* Only HTTP inbound traffic is allowed. No inbound RMI communication is allowed. There cannot be any peer-to-peer communication between WebLogic Server instances.

* There is no support for multiple servers or clusters within the domain. An admin server would be running with the application(s) deployed to it. In-memory session replication/high-availability is not supported.

* Only stateless applications are supported.
  * The server will start with a brand new image (on an entirely different VM possibly) on restarts and hence it cannot rely on state of previous runs.
  The file system is ephemeral and will be reset after a restart of the server instance. This means Transaction recovery is not supported after restarts.
  This also includes no support for messaging using persistent file stores.
  WebLogic LLR for saving transaction logs on database and JDBC JMS store options are both not possible as the identify of the server would be unique and different on each run.

* Changes made via the WebLogic Admin Console will not persist across restarts for the same reasons mentioned previously, domain customizations should be made at staging time using the buildpack configuration options.

* Server logs are transient and are not available across restarts on the container file system, however can have Cloud Foundry loggregator send logs to a [syslog drain endpoint like Splunk][].

* The buildpack does not handle security aspects (Authentication or Authorization). It only uses the embedded ldap server for creating and using the single WebLogic Admin user. Its possible to extend apply security policies by tweaking the domain creation.

* Only base WebLogic domains are currently supported. There is no support for other layered products like SOA Suite, Web Center or IDM in the buildpack.

## Contributing
[Pull requests][] are welcome; see the [contributor guidelines][] for details.

## License
This buildpack is released under version 2.0 of the [Apache License][].

[Apache License]: http://www.apache.org/licenses/LICENSE-2.0
[Cloud Foundry]: http://www.cloudfoundry.com
[contributor guidelines]: CONTRIBUTING.md
[GitHub's forking functionality]: https://help.github.com/articles/fork-a-repo
[Grails]: http://grails.org
[Groovy]: http://groovy.codehaus.org
[Installing Cloud Foundry on Vagrant]: http://blog.cloudfoundry.com/2013/06/27/installing-cloud-foundry-on-vagrant/
[Play Framework]: http://www.playframework.com
[pull request]: https://help.github.com/articles/using-pull-requests
[Pull requests]: http://help.github.com/send-pull-requests
[Spring Boot]: http://projects.spring.io/spring-boot/
[java-buildpack]: http://github.com/cloudfoundry/java-buildpack/
[Oracle WebLogic Application Server]: http://www.oracle.com/technetwork/middleware/weblogic/overview/index.html
[bosh-lite]: http://github.com/cloudfoundry/bosh-lite/
[Pivotal Web Services Marketplace]: http://docs.run.pivotal.io/marketplace/services/
[User Provided Services]: http://docs.run.pivotal.io/devguide/services/user-provided.html
[Linux 64 bit JRE]: http://javadl.sun.com/webapps/download/AutoDL?BundleId=83376
[WebLogic Server]: http://www.oracle.com/technetwork/middleware/weblogic/downloads/index.html
[limited footprint]: http://docs.oracle.com/middleware/1212/wls/START/overview.htm#START234
[syslog drain endpoint like Splunk]: http://www.youtube.com/watch?v=rk_K_AAHEEI

=======
weblogic-buildpack
==================

