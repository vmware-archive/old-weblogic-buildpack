# WebLogic Domain Config

The **`weblogic-buildpack`** creates a WebLogic Server Domain using a domain configuration yaml file present under the **`.wls`** folder of the application.

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
              .wls/script/wlsDomainCreate.py                 <--------- WLST Script
              .wls/security/
              .wls/security/securityConfig.yml
              .wls/wlsDomainConfig.yml                       <--------- Domain Config file

       ```

The contents of the domain config file specify the name of the domain and server, name and password of the admin user. Additionally, it can also specify whether to enable Console and Production Mode.
The parameters are used by the buildpack during creation of the domain using the wlst script provided along with the application.
Presence of this file along with the script is mandatory for creation of the WebLogic Domain.

Sample domain config (from [wlsDomainConfig.yml](resources/wls/wlsDomainConfig.yml)
```

# Configuration for the WebLogic Domain
---

# Need serverName, domainName, user and password filled in
#

Domain:
  serverName: testServer
  domainName: cfDomain
  wlsUser: weblogic
  wlsPasswd: welcome1
  consoleEnabled: true
  prodModeEnabled: false

```

* **`serverName`** denotes the name of the generated server
* **`domainName`** denotes the name of the generated domain
* **`wlsUser`** denotes the name of the admin user
* **`wlsPaswd`** denotes the password of the admin user
* **`consoleEnabled`** enables or disables WLS Admin Console deployment
* **`prodModeEnabled`** enables or disables Production Mode in WLS.