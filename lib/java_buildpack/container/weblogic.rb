# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright (c) 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/container'
require 'java_buildpack/container/container_utils'
require 'java_buildpack/util/format_duration'
require 'java_buildpack/util/java_main_utils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/component/java_opts'
require 'java_buildpack/container/wls/service_bindings_reader'
require 'yaml'
require 'tmpdir'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for WebLogic Server (WLS) based
  # applications on Cloud Foundry.
  class Weblogic < JavaBuildpack::Component::VersionedDependencyComponent
    include JavaBuildpack::Util

    def initialize(context)
      super(context)

      if supports?
        @wls_version, @wls_uri = JavaBuildpack::Repository::ConfiguredItem
        .find_item(@component_name, @configuration) { |candidate_version| candidate_version.check_size(3) }


        @preferAppConfig = @configuration[PREFER_APP_CONFIG]
        @startInWlxMode  = @configuration[START_IN_WLX_MODE]

        @wlsSandboxRoot           = @droplet.sandbox
        @wlsDomainPath            = @wlsSandboxRoot + WLS_DOMAIN_PATH
        @appConfigCacheRoot       = @application.root + APP_WLS_CONFIG_CACHE_DIR
        @appServicesConfig        = @application.services

        # Root of Buildpack bundled config cache - points to <weblogic-buildpack>/resources/wls
        @buildpackConfigCacheRoot = BUILDPACK_WLS_CONFIG_CACHE_DIR

        load()

      else
        @wls_version, @wls_uri       = nil, nil

      end

    end


    # @macro base_component_detect
    def detect
      if @wls_version
        [wls_id(@wls_version)]
      else
        nil
      end
    end

    def compile1

       testServiceBindingParsing()
    end

    # @macro base_component_compile
    def compile

      download_wls
      configure
      link_to(@application.root.children, root)
      #@droplet.additional_libraries.link_to web_inf_lib
      create_dodeploy
    end

    def release

      setupJvmArgs
      createSetupEnvAndLinksScript

      [
          @droplet.java_home.as_env_var,
          "USER_MEM_ARGS=\"#{@droplet.java_opts.join(' ')}\"",
          "/bin/sh ./#{SETUP_ENV_AND_LINKS_SCRIPT}; #{@domainHome}/startWebLogic.sh"
      ].flatten.compact.join(' ')
    end


    protected

    # The unique identifier of the component, incorporating the version of the dependency (e.g. +wls=12.1.2+)
    #
    # @param [String] version the version of the dependency
    # @return [String] the unique identifier of the component
    def wls_id(version)
      "#{Weblogic.to_s.dash_case}=#{version}"
    end

    # The unique identifier of the component, incorporating the version of the dependency (e.g. +wls-buildpack-support=12.1.2+)
    #
    # @param [String] version the version of the dependency
    # @return [String] the unique identifier of the component
    def support_id(version)
      "wls-buildpack-support=#{version}"
    end

    # Whether or not this component supports this application
    #
    # @return [Boolean] whether or not this component supports this application
    def supports?
      wls? && !JavaBuildpack::Util::JavaMainUtils.main_class(@application)
    end

    private


    # Expect to see a '.wls' folder containing domain configurations and script to create the domain within the App bits
    APP_WLS_CONFIG_CACHE_DIR       = '.wls'.freeze

    # Default WebLogic Configurations packaged within the buildpack
    BUILDPACK_WLS_CONFIG_CACHE_DIR = Pathname.new(File.expand_path('../../../resources/wls', File.dirname(__FILE__))).freeze

    # Prefer App Bundled Config or Buildpack bundled Config
    PREFER_APP_CONFIG           = 'preferAppConfig'.freeze

    # Prefer App Bundled Config or Buildpack bundled Config
    START_IN_WLX_MODE           = 'startInWlxMode'.freeze

    # Following are relative to the .wls folder all under the APP ROOT
    WLS_SCRIPT_CACHE_DIR        = 'script'.freeze
    WLS_JVM_CONFIG_DIR          = 'jvm'.freeze
    WLS_JMS_CONFIG_DIR          = 'jms'.freeze
    WLS_JDBC_CONFIG_DIR         = 'jdbc'.freeze
    WLS_FOREIGN_JMS_CONFIG_DIR  = 'foreignjms'.freeze
    WLS_PRE_JARS_CACHE_DIR      = 'preJars'.freeze
    WLS_POST_JARS_CACHE_DIR     = 'postJars'.freeze

    # Parent Location to save/store the application during deployment
    DOMAIN_APPS_FOLDER             = 'apps'.freeze

    WLS_SERVER_START_SCRIPT     = 'startWebLogic.sh'.freeze
    WLS_COMMON_ENV_SCRIPT       = 'commEnv.sh'.freeze
    WLS_CONFIGURE_SCRIPT        = 'configure.sh'.freeze

    WLS_SERVER_START_TOKEN      = '\${DOMAIN_HOME}/bin/startWebLogic.sh \$*'.freeze
    SETUP_ENV_AND_LINKS_SCRIPT  = 'setupPathsAndEnv.sh'.freeze

    # WLS_DOMAIN_PATH is relative to sandbox
    WLS_DOMAIN_PATH          = 'domains/'.freeze

    # Other constants
    SERVER_VM                = '-server'.freeze
    CLIENT_VM                = '-client'.freeze
    WEB_INF_DIRECTORY        = 'WEB-INF'.freeze
    JAVA_BINARY              = 'java'.freeze

    APP_NAME                 = 'ROOT'.freeze


    # @return [Hash] the configuration or an empty hash if the configuration file does not exist
    def load(should_log = true)

      # Determine the configs that should be used to drive the domain creation.
      # Can be the App bundled configs
      # or the buildpack bundled configs

      # During development when the domain structure is still in flux, use App bundled config to test/tweak the domain.
      # Once the domain structure is finalized, save the configs as part of the buildpack and then only pass along the bare bones domain config and jvm config.
      # Ignore the rest of the app configs.

      configCacheRoot = determineConfigCacheLocation

      @wlsDomainYamlConfigFile  = Dir.glob("#{@appConfigCacheRoot}/*.yml")[0]

      # If there is no Domain Config yaml file, copy over the buildpack bundled basic domain configs.
      # Create the appConfigCacheRoot '.wls' directory under the App Root as needed
      if (@wlsDomainYamlConfigFile.nil?)
        system "mkdir #{@appConfigCacheRoot} 2>/dev/null; cp  #{@buildpackConfigCacheRoot}/*.yml #{@appConfigCacheRoot}"
        @wlsDomainYamlConfigFile  = Dir.glob("#{@appConfigCacheRoot}/*.yml")[0]
        logger.debug { "No Domain Configuration yml file found, creating one from the buildpack bundled template!!" }
      end

      domainConfiguration       = YAML.load_file(@wlsDomainYamlConfigFile)
      logger.debug { "WLS Domain Configuration: #{@wlsDomainYamlConfigFile}: #{domainConfiguration}" }

      @domainConfig  = domainConfiguration["Domain"]
      @domainName    = @domainConfig['domainName']
      @domainHome    = @wlsDomainPath + @domainName
      @domainAppsDir = @domainHome + DOMAIN_APPS_FOLDER

      # There can be multiple service definitions (for JDBC, JMS, Foreign JMS services)
      # Based on chosen config location, load the related files

      wlsJmsConfigFiles        = Dir.glob("#{configCacheRoot}/#{WLS_JMS_CONFIG_DIR}/*.yml")
      wlsJdbcConfigFiles       = Dir.glob("#{configCacheRoot}/#{WLS_JDBC_CONFIG_DIR}/*.yml")
      wlsForeignJmsConfigFile  = Dir.glob("#{configCacheRoot}/#{WLS_FOREIGN_JMS_CONFIG_DIR}/*.yml")

      @wlsCompleteDomainConfigsYml = [ @wlsDomainYamlConfigFile ]
      @wlsCompleteDomainConfigsYml +=  wlsJdbcConfigFiles + wlsJmsConfigFiles + wlsForeignJmsConfigFile

      logger.debug { "Configuration files used for Domain creation: #{@wlsCompleteDomainConfigsYml}" }

      # Filtered Pathname has a problem with non-existing files
      # It checks for their existence. So, get the path as string and add the props file name for the output file
      @wlsCompleteDomainConfigsProps     = @wlsDomainYamlConfigFile.to_s.sub(".yml", ".props")

      # For now, expecting only one script to be run to create the domain
      @wlsDomainConfigScript    = Dir.glob("#{configCacheRoot}/#{WLS_SCRIPT_CACHE_DIR}/*.py")[0]

      # If there is no Domain Script, use the buildpack bundled script.
      if (@wlsDomainConfigScript.nil?)
        @wlsDomainConfigScript  = Dir.glob("#{@buildpackConfigCacheRoot}/#{WLS_SCRIPT_CACHE_DIR}/*.py")[0]
        logger.debug { "No Domain creation script found, reusing one from the buildpack bundled template!!" }
      end


      logger.debug { "Configurations for WLS Domain" }
      logger.debug { "--------------------------------------" }
      logger.debug { "  Domain Name                : #{@domainName}" }
      logger.debug { "  Domain Location            : #{@domainHome}" }
      logger.debug { "  Apps Directory             : #{@domainAppsDir}" }
      logger.debug { "  Using App bundled Config?  : #{@domainAppsDir}" }

      logger.debug { "  Domain creation script     : #{@wlsDomainConfigScript}" }
      logger.debug { "  Input WLS Yaml Configs     : #{@wlsCompleteDomainConfigsYml}" }
      logger.debug { "--------------------------------------" }

      domainConfiguration || {}
    end

    # Load the app bundled configurations and re-configure as needed the JVM parameters for the Server VM
    # @return [Hash] the configuration or an empty hash if the configuration file does not exist
    def setupJvmArgs

      # Go with some defaults
      minPermSize = 128
      maxPermSize = 256
      minHeapSize = 512
      maxHeapSize = 1024
      otherJvmOpts = " -verbose:gc -Xloggc:gc.log -XX:+PrintGCDetails -XX:+PrintGCTimeStamps "

      # Expect only one server instance to run, so there can be only one jvm config
      @wlsJvmConfigFile         = Dir.glob("#{@appConfigCacheRoot}/#{WLS_JVM_CONFIG_DIR}/*.yml")[0]

      # If there is no Domain Script, use the buildpack bundled script.
      if (@wlsJvmConfigFile.nil?)
        @wlsJvmConfigFile = Dir.glob("#{@buildpackConfigCacheRoot}/#{WLS_JVM_CONFIG_DIR}/*.yml")[0]
      end

      if !@wlsJvmConfigFile.nil?

        jvmConfiguration = YAML.load_file(@wlsJvmConfigFile)
        logger.debug { "WLS JVM Configuration: #{@wlsJvmConfigFile}: contents #{jvmConfiguration}" }

        @jvmConfig    = jvmConfiguration["JVM"]

        minPermSize = @jvmConfig['minPerm']
        maxPermSize = @jvmConfig['maxPerm']
        logger.debug { "JVM config passed with App: #{@jvmConfig.to_s}" }

        # Set Default Min and Max Heap Size for WLS
        minHeapSize  = @jvmConfig['minHeap']
        maxHeapSize  = @jvmConfig['maxHeap']
        otherJvmOpts = @jvmConfig['otherJvmOpts']

      end

      logger.debug { "JVM config passed via droplet java_opts : #{@droplet.java_opts.to_s}" }
      javaOptTokens = @droplet.java_opts.join(' ').split

      javaOptTokens.each { |token|

        intValueInMB =  token[/[0-9]+/].to_i
        # The values incoming can be in MB or KB
        # Anything over 61440 is atleast in KB and needs to be converted to MB
        intValueInMB = (intValueInMB / 1024) if (intValueInMB > 61440)

        if token[/-XX:PermSize/]
          minPermSize = intValueInMB
          minPermSize = 128 if (minPermSize < 128)

        elsif token[/-XX:MaxPermSize/]
          maxPermSize = intValueInMB
          maxPermSize = 256 if (maxPermSize < 128)

        elsif token[/-Xms/]
          minHeapSize = intValueInMB
        elsif token[/-Xmx/]
          maxHeapSize = intValueInMB
        else
          otherJvmOpts = otherJvmOpts + " " + token
        end

      }

      @droplet.java_opts.clear()

      @droplet.java_opts << "-Xms#{minHeapSize}m"
      @droplet.java_opts << "-Xmx#{maxHeapSize}m"
      @droplet.java_opts << "-XX:PermSize=#{minPermSize}m"
      @droplet.java_opts << "-XX:MaxPermSize=#{maxPermSize}m"

      @droplet.java_opts << otherJvmOpts

      # Set the server listen port using the $PORT argument set by the warden container
      @droplet.java_opts.add_system_property 'weblogic.ListenPort', '$PORT'

      # Check whether to start in Wlx Mode that would disable JMS, EJB and JCA
      if @startInWlxMode
        @droplet.java_opts.add_system_property 'serverType', 'wlx'
      end

      logger.debug { "Consolidated Java Options for Server: #{@droplet.java_opts.join(' ')}" }

    end


    # Create a setup script that would recreate staging env's path structure inside the actual DEA runtime env and also embed additional jvm arguments at server startup
    def createSetupEnvAndLinksScript

      # The Java Buildpack for WLS creates the complete domain structure and other linkages during staging. The directory used for staging is at /tmp/staged/app
      # But the actual DEA execution occurs at /home/vcap/app. This discrepancy can result in broken paths and non-startup of the server.
      # So create linkage from /tmp/staged/app to actual environment of /home/vcap/app when things run in real execution
      # Also, this script needs to be invoked before starting the server as it will create the links and also tweak the server args (to listen on correct port, use user supplied jvm args)
      File.open(@application.root.to_s + "/" + SETUP_ENV_AND_LINKS_SCRIPT, 'w') do |f|

        f.puts "#!/bin/sh"
        f.puts "# The Java Buildpack for WLS creates complete domain structure and other linkages during staging at /tmp/staged/app location"
        f.puts "# But the actual DEA execution occurs at /home/vcap/app. This discrepancy can result in broken paths and non-startup of the server."
        f.puts "# So create linkage from /tmp/staged/app to actual environment of /home/vcap/app when things run in real execution"
        f.puts "# Create paths that match the staging env as scripts will break otherwise"
        f.puts ""
        f.puts "if [ ! -d \"/tmp/staged\" ]; then"
        f.puts "   /bin/mkdir /tmp/staged"
        f.puts "fi;"
        f.puts "if [ ! -d \"/tmp/staged/app\" ]; then"
        f.puts "   /bin/ln -s `pwd` /tmp/staged/app"
        f.puts "fi;"
        f.puts ""

        wlsPreClasspath  = "export PRE_CLASSPATH=\"#{@domainHome}/#{WLS_PRE_JARS_CACHE_DIR}/*\""
        wlsPostClasspath = "export POST_CLASSPATH=\"#{@domainHome}/#{WLS_POST_JARS_CACHE_DIR}/*\""

        f.puts "#Export User defined memory, jvm settings, pre/post classpaths inside the startWebLogic.sh"
        f.puts "/bin/sed -i.bak 's#^DOMAIN_HOME#export USER_MEM_ARGS=\"#{@droplet.java_opts.join(' ')} \";\\n#{wlsPreClasspath}\\n#{wlsPostClasspath}\\n&#1' #{@domainHome}/startWebLogic.sh"

      end

    end

    def link_application
      FileUtils.rm_rf root
      FileUtils.mkdir_p root
      @application.children.each { |child| FileUtils.cp_r child, root }
    end

    def expand(file)
      expand_start_time = Time.now

      print "-----> Expanding WebLogic to #{@droplet.sandbox.relative_path_from(@droplet.root)}\n"

      FileUtils.rm_rf @wlsSandboxRoot
      FileUtils.mkdir_p @wlsSandboxRoot

      system "/usr/bin/unzip #{file.path} -d #{@wlsSandboxRoot} >/dev/null"

      puts "(#{(Time.now - expand_start_time).duration})"
    end

    def configure()
      configure_start_time = Time.now

      print "-----> Configuring WebLogic under #{@wlsSandboxRoot.relative_path_from(@droplet.root)}\n"


      javaBinary      = Dir.glob("#{@wlsSandboxRoot}" + "/../**/" + JAVA_BINARY)[0]
      configureScript = Dir.glob("#{@wlsSandboxRoot}" + "/**/" + WLS_CONFIGURE_SCRIPT)[0]

      logger.debug { "Java Binary is located at : #{javaBinary}" }
      logger.debug { "WLS configure script is located at : #{configureScript}" }
      logger.debug { "Application is located at : #{@application.root}" }

      @javaHome = File.dirname(javaBinary) + "/.."
      @wlsInstall = File.dirname(configureScript)
      @wlsHome = Dir.glob("#{@wlsInstall}/wlserver*")[0].to_s

      # Now add or update the Domain path and Wls Home inside the wlsDomainYamlConfigFile
      updateDomainConfigFile(@wlsDomainYamlConfigFile)

      logger.debug { "Configurations for Java WLS Buildpack" }
      logger.debug { "--------------------------------------" }
      logger.debug { "  Sandbox Root  : #{@wlsSandboxRoot} " }
      logger.debug { "  JAVA_HOME     : #{@javaHome} " }
      logger.debug { "  WLS_INSTALL   : #{@wlsInstall} "}
      logger.debug { "  WLS_HOME      : #{@wlsHome}" }
      logger.debug { "  DOMAIN HOME   : #{@domainHome}" }
      logger.debug { "--------------------------------------" }


      system "/bin/chmod +x #{configureScript}"

      # Run configure.sh so the actual files are unpacked fully and paths are configured correctly
      # Need to use pipeline as we need to provide inputs to scripts downstream

      logger.debug { "Running configure script!!" }

      # Use this while running on Mac to pick the correct JDK location
      if mac?

        print "       Warning!!! Running on Mac, cannot use linux java binaries downloaded earlier...!!\n"
        print "       Trying to find local java instance on Mac\n"

        logger.debug { "Warning!!! Running on Mac, cannot use linux java binaries downloaded earlier...!!" }
        logger.debug { "Trying to find local java instance on Mac" }

        javaBinaryLocations = Dir.glob("/Library/Java/JavaVirtualMachines/**/" + JAVA_BINARY)
        javaBinaryLocations.each { |javaBinaryCandidate|

          # The full installs have $JAVA_HOME/jre/bin/java path
          @javaHome =  File.dirname(javaBinaryCandidate) + "/.." if javaBinaryCandidate[/jdk1.7/]
        }
        print "       Warning!!! Using JAVA_HOME at #{@javaHome} \n"
        logger.debug { "Warning!!! Using JAVA_HOME at #{@javaHome}" }

      end

      print "       Starting WebLogic Install\n"
      logger.debug { "Starting WebLogic Install" }

      system "export JAVA_HOME=#{@javaHome}; echo no |  #{configureScript} > #{@wlsInstall}/configureRun.log"
      logger.debug { "Finished running configure script, output saved at #{@wlsInstall}/configureRun.log" }

      # Modify WLS commEnv Script to use -server rather than -client
      modifyJvmTypeInCommEnv()


      # Determine the configs that should be used to drive the domain creation.
      # Is it the App bundled configs or the buildpack bundled configs
      # The JVM and Domain configs of the App would always be used for domain/server names and startup arguments
      configCacheRoot = determineConfigCacheLocation

      # Consolidate all the user defined service definitions provided via the app,
      # along with anything else that comes via the Service Bindings via the environment (VCAP_SERVICES) during staging/execution of the droplet.

      system "/bin/rm  #{@wlsCompleteDomainConfigsProps} 2>/dev/null"

      JavaBuildpack::Container::Wls::ServiceBindingsReader.createServiceDefinitionsFromFileSet(@wlsCompleteDomainConfigsYml, configCacheRoot, @wlsCompleteDomainConfigsProps)
      JavaBuildpack::Container::Wls::ServiceBindingsReader.createServiceDefinitionsFromBindings(@appServicesConfig, @wlsCompleteDomainConfigsProps)

      logger.debug { "Done generating Domain Configuration Property file for WLST: #{@wlsCompleteDomainConfigsProps}" }
      logger.debug { "--------------------------------------" }

      logger.debug { "Configurations for WLS Domain Creation" }
      logger.debug { "--------------------------------------" }
      logger.debug { "  Domain Name                : #{@domainName}" }
      logger.debug { "  Domain Location            : #{@domainHome}" }
      logger.debug { "  App Deployment Name        : #{APP_NAME}" }
      logger.debug { "  Domain Apps Directory      : #{@domainAppsDir}" }
      logger.debug { "  Using App bundled Config?  : #{@preferAppConfig}" }
      logger.debug { "  Domain creation script     : #{@wlsDomainConfigScript}" }
      logger.debug { "  WLST Input Config          : #{@wlsCompleteDomainConfigsProps}" }
      logger.debug { "--------------------------------------" }


      # Run wlst.sh to generate the domain as per the requested configurations

      wlstScript = Dir.glob("#{@wlsInstall}" + "/**/wlst.sh")[0]
      system "/bin/chmod +x #{wlstScript}; export JAVA_HOME=#{@javaHome}; #{wlstScript}  #{@wlsDomainConfigScript} #{@wlsCompleteDomainConfigsProps} > #{@wlsInstall}/wlstDomainCreation.log"

      logger.debug { "WLST finished generating domain under #{@domainHome.relative_path_from(@droplet.root)}. WLST log saved at: #{@wlsInstall}/wlstDomainCreation.log" }

      linkJarsToDomain

      print "-----> Finished configuring WebLogic Domain under #{@domainHome.relative_path_from(@droplet.root)}.\n"
      print "       WLST log saved at: #{@wlsInstall}/wlstDomainCreation.log\n"

      puts "(#{(Time.now - configure_start_time).duration})"
    end


    # Generate the property file based on app bundled configs for test against WLST
    def testServiceBindingParsing()

      configCacheRoot = determineConfigCacheLocation

      JavaBuildpack::Container::Wls::ServiceBindingsReader.createServiceDefinitionsFromFileSet(@wlsCompleteDomainConfigsYml, configCacheRoot, @wlsCompleteDomainConfigsProps)
      JavaBuildpack::Container::Wls::ServiceBindingsReader.createServiceDefinitionsFromBindings(@appServicesConfig, @wlsCompleteDomainConfigsProps)
      logger.debug { "Done generating Domain Configuration Property file for WLST: #{@wlsCompleteDomainConfigsProps}" }
      logger.debug { "--------------------------------------" }

    end


    def download_wls
      download(@wls_version, @wls_uri) { |file| expand file }
    end

    def link_to(source, destination)
      FileUtils.mkdir_p destination
      source.each { |path|
        # Ignore the .java-buildpack log and .java-buildpack subdirectory containing the app server bits
        next if path.to_s[/\.java-buildpack/]
        next if path.to_s[/\.wls/]
        (destination + path.basename).make_symlink(path.relative_path_from(destination))
      }
    end

    def wlsDomain
      @domainHome
    end

    def wlsDomainlib
      @domainHome + 'lib'
    end

    def webapps
      @domainAppsDir
    end

    def root
      webapps + APP_NAME
    end

    def web_inf_lib
      @application.root + 'WEB-INF/lib'
    end

    def web_inf?
      (@application.root + 'WEB-INF').exist?
    end

    def wls?
      searchPath = (@application.root).to_s + "/**/weblogic*xml"
      wlsConfigPresent = Dir.glob(searchPath).length > 0

      appWlsConfigCacheExists = (@application.root + APP_WLS_CONFIG_CACHE_DIR).exist?
      isBaseWebApp = web_inf?

      logger.debug { "Running Detection on App: #{@application.root}" }
      logger.debug { "  Checking for presence of #{APP_WLS_CONFIG_CACHE_DIR} folder under root of the App or weblogic deployment descriptors within App" }
      logger.debug { "  Does #{APP_WLS_CONFIG_CACHE_DIR} folder exist under root of the App? : #{appWlsConfigCacheExists}" }
      logger.debug { "  Does  weblogic deployment descriptors exist within App? : #{wlsConfigPresent}" }
      logger.debug { "  Or is it a simple Web Application with WEB-INF folder? : " + isBaseWebApp.to_s }

      (appWlsConfigCacheExists || wlsConfigPresent || web_inf?)
    end

    # Determine which configurations should be used for driving the domain creation - App or buildpack bundled configuration
    def determineConfigCacheLocation

      if (@preferAppConfig)

        # Use the app bundled configuration and domain creation scripts.
        @appConfigCacheRoot

      else

        # Use the buidlpack's bundled configuration and domain creation scripts (under resources/wls)
        # But the jvm and domain configuration files from the app bundle will be used, rather than the buildpack version.
        @buildpackConfigCacheRoot

      end

    end


    def updateDomainConfigFile(wlsDomainConfigFile)


      original = File.open(wlsDomainConfigFile, 'r') { |f| f.read }

      # Remove any existing references to wlsHome or domainPath
      modified = original.gsub(/  wlsHome:.*$\n/, "")
      modified = modified.gsub(/  domainPath:.*$\n/, "")
      modified = modified.gsub(/  appName:.*$\n/, "")
      modified = modified.gsub(/  appSrcPath:.*$\n/, "")

      # Add new references to wlsHome and domainPath
      modified << "  wlsHome: #{@wlsHome.to_s}\n"
      modified << "  domainPath: #{@wlsDomainPath.to_s}\n"
      modified << "  appName: #{APP_NAME}\n"
      modified << "  appSrcPath: #{@domainAppsDir.to_s + "/#{APP_NAME}"}\n"

      File.open(wlsDomainConfigFile, 'w') { |f| f.write modified }

      logger.debug { "Added entry for WLS_HOME to point to #{@wlsHome} in domain config file" }
      logger.debug { "Added entry for DOMAIN_PATH to point to #{@wlsDomainPath} in domain config file" }

    end

    def customizeWLSServerStart(startServerScript, additionalParams)

      withAdditionalEntries = additionalParams + "\r\n" + WLS_SERVER_START_TOKEN
      original = File.open(startServerScript, 'r') { |f| f.read }
      modified = original.gsub(/WLS_SERVER_START_TOKEN/, withAdditionalEntries)
      File.open(startServerScript, 'w') { |f| f.write modified }

      logger.debug { "Modified #{startServerScript} with additional parameters: #{additionalParams} " }

    end

    def modifyJvmTypeInCommEnv()

      Dir.glob("#{@wlsInstall}/**/commEnv.sh").each { |commEnvScript|

        original = File.open(commEnvScript, 'r') { |f| f.read }
        modified = original.gsub(/#{CLIENT_VM}/, SERVER_VM)
        File.open(commEnvScript, 'w') { |f| f.write modified }
      }

      logger.debug { "Modified commEnv.sh files to use '-server' vm from the default '-client' vm!!" }

    end

    def linkJarsToDomain()

      @wlsPreClasspathJars         = Dir.glob("#{@appConfigCacheRoot}/#{WLS_PRE_JARS_CACHE_DIR}/*")
      @wlsPostClasspathJars        = Dir.glob("#{@appConfigCacheRoot}/#{WLS_POST_JARS_CACHE_DIR}/*")

      logger.debug { "Linking pre and post jar directories relative to the Domain" }

      system "/bin/ln -s #{@appConfigCacheRoot}/#{WLS_PRE_JARS_CACHE_DIR} #{@domainHome}/#{WLS_PRE_JARS_CACHE_DIR} 2>/dev/null"
      system "/bin/ln -s #{@appConfigCacheRoot}/#{WLS_POST_JARS_CACHE_DIR} #{@domainHome}/#{WLS_POST_JARS_CACHE_DIR} 2>/dev/null"

    end

    def logger
      JavaBuildpack::Logging::LoggerFactory.get_logger Weblogic
    end

    def create_dodeploy
      FileUtils.touch(webapps + 'REDEPLOY')
    end

    def parameterize_http_port
      #standalone_config = "#{wls_home}/standalone/configuration/standalone.xml"
      #original = File.open(standalone_config, 'r') { |f| f.read }
      #modified = original.gsub(/<socket-binding name="http" port="8080"\/>/, '<socket-binding name="http" port="${http.port}"/>')
      #File.open(standalone_config, 'w') { |f| f.write modified }
    end

    def disable_welcome_root
      #standalone_config = "#{wls_home}/standalone/configuration/standalone.xml"
      #original = File.open(standalone_config, 'r') { |f| f.read }
      #modified = original.gsub(/<virtual-server name="default-host" enable-welcome-root="true">/, '<virtual-server name="default-host" enable-welcome-root="false">')
      #File.open(standalone_config, 'w') { |f| f.write modified }
    end

    def disable_console
      #standalone_config = "#{wls_home}/standalone/configuration/standalone.xml"
      #original = File.open(standalone_config, 'r') { |f| f.read }
      #modified = original.gsub(/<virtual-server name="default-host" enable-welcome-root="true">/, '<virtual-server name="default-host" enable-welcome-root="false">')
      #File.open(standalone_config, 'w') { |f| f.write modified }
    end

    def windows?
      (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
    end

    def mac?
      (/darwin/ =~ RUBY_PLATFORM) != nil
    end

    def unix?
      !OS.windows?
    end

    def linux?
      OS.unix? and not OS.mac?
    end

  end

end

