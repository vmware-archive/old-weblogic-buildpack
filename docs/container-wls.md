# WebLogic Domain Config

The **`weblogic-buildpack`** creates a WebLogic Server Domain using a domain configuration yaml file present under the **`.wls`** folder of the application.

The [weblogic.yml](../config/weblogic.yml) file within the buildpack is used to specify the WebLogic Server Binary download site.
It also manages some configurations used for the WLS Domain creation.

   * The WebLogic Server release bits and jdk binaries should be accessible for download from a server (can be internal or public facing) for the buildpack to create the necessary configurations along with the app bits.
     Download the [Linux 64 bit JRE][] version and [WebLogic Server][] generic version.

   * Edit the repository_root of [weblogic.yml](config/weblogic.yml) to point to the server hosting the weblogic binary.

     Sample `repository_root` for weblogic.yml (under weblogic-buildpack/config)

      ```
      --
        version: 12.1.+
        repository_root: "http://12.1.1.1:7777/fileserver/wls"
        preferAppConfig: false
        startInWlxMode: false

      ```

      The buildpack would look for an `index.yml` file at the specified repository_root url for obtaining WebLogic related bits.
      The index.yml at the repository_root location should have a entry matching the weblogic server version and the corresponding release bits

      ```
        ---
          12.1.2: http://12.1.1.1:7777/fileserver/wls/wls1212_dev.zip
      ```

      Ensure the WebLogic Server binary is available at the location indicated by the index.yml referred by the weblogic repository_root

  * The **preferAppConfig** flag allows overriding of the app bundle configurations with that of the buildpack bundle configurations.

  The weblogic-buildpack can override the app bundled configuration for subsystems like jdbc, jms etc.
  The script for generating the domain would be pulled from the buildpack configuration (under resources/wls/script).

  But the name of the domain, server and user credentials would be pulled from Application bundled config files so each application can be named differently.
  The jvm configuration would also be pulled from the app bundled config (for app specific memory requirements).


        ```
        version: 12.1.+
        repository_root: http://12.1.1.1:7777/fileserver/wls
        preferAppConfig: false

        ```

  Setting the  **`preferAppConfig`** to **`true`** would imply the app bundled configs (under .wls of the App Root) would always be used for final domain creation.
  Setting the parameter to **`false`** would imply the buildpack's configurations (under resources\wls\) have higher precedence over the app bundled configs and be used to configure the domain.
  The Application supplied domain config and jvm config file would be used for names of the domain, server, user credentials and jvm memory and command line settings.
  The script for the domain creation would however come from the buildpack.

  * The **startInWlxMode** can be used to configure the server to run with a limited runtime footprint by avoiding certain subsystems like  EJB, JMS, JCA etc.

          ```
          version: 12.1.+
          repository_root: http://12.1.1.1:7777/fileserver/wls
          preferAppConfig: false
          startInWlxMode: false

          ```


  Setting the **startInWlxMode** to true would disable the EJB, JMS and JCA layers and reducing the overall memory footprint required by WLS Server.
  This is ideal for running pure web applications that don't use EJBs or messaging.
  If there are any EJBs or jms modules/destinations configured, the activation of the resources will result in errors at server startup.

  Setting the **startInWlxMode** to false would allow the full blown server mode.

  Please refer to the WebLogic server documentation on the [limited footprint][] option for more details.


[Linux 64 bit JRE]: http://javadl.sun.com/webapps/download/AutoDL?BundleId=83376
[WebLogic Server]: http://www.oracle.com/technetwork/middleware/weblogic/downloads/index.html
[limited footprint]: http://docs.oracle.com/middleware/1212/wls/START/overview.htm#START234