# WebLogic Domain Config

The **`weblogic-buildpack`** creates a WebLogic Server Domain using a domain configuration yaml file present under the **`.wls`** folder of the application along with a WLST Script.

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
              **.wls/script/wlsDomainCreate.py                 <--------- WLST Script**
              .wls/security/
              .wls/security/securityConfig.yml
              **.wls/wlsDomainConfig.yml                       <--------- Domain Config file**

       ```

The domain script is bundled under the `.wls/script` folder of the application package.
The contents of the various yaml files ( domain, jdbc, jms, foreignjms,... etc.) are consolidated to generate a new properties file (wlsDomainConfig.props). This happens during the compile stage of the weblogic-buildpack.
This file is passed to WLST along with the script to generate the domain.

The current script creates a domain based on the domain config, followed by jdbc, jms and foreign jms resources creation.
The script deploys the application towards the end of the domain creation.

Sample output logged in the **`.java-buildpack.log`** (created under the exploded app folder):

```
2014-03-27T10:03:51.92-0700 [Weblogic]                       DEBUG Processing App bundled Service Definition : ["Domain", {"serverName"=>"testServer", "domainName"=>"cfDomain",
                                                                        "wlsHome"=>"/Users/sparameswaran/workspace/wlsSampleApp2/.java-buildpack/weblogic/wls12120/wlserver",
                                                                        "domainPath"=>"/Users/sparameswaran/workspace/wlsSampleApp2/.java-buildpack/weblogic/domains/"}]
2014-03-27T10:03:51.92-0700 [Weblogic]                       DEBUG Done generating Domain Configuration Property file for WLST: /Users/sparameswaran/workspace/wlsSampleApp2/.wls/wlsDomainConfig.props
2014-03-27T10:03:51.92-0700 [Weblogic]                       DEBUG --------------------------------------
2014-03-27T10:04:16.10-0700 [Weblogic]                       DEBUG WLST finished generating domain. Log file saved at:
                                                                        /Users/sparameswaran/workspace/wlsSampleApp2/.java-buildpack/weblogic/wls12120/wlstDomainCreation.log

```

A sample domain creation script is bundled with the buildpack ([wlsDomainCreate.py](resources/wls/script/wlsDomainCreate.yml) .
The parameter in the script and the config files are bound tightly to each other. Changes to the parameters in the config files can break the script and vice-versa.

Wrong alignments in conditional blocks or mix-up of String and Int parameters can break the WLST execution without clear error messages.
Add debugs (print statements) to the script when any modification is required to build out the domain to ensure all steps are completed.
Run the detect/compile stages manually and verify/test the resulting domain to ensure its configured correctly.

**Note:**
There are currently no security related configuration actions included in the script.
Add/update any security related configurations and actions as needed to both the script and security config file.