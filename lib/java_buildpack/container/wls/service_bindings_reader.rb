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

require 'pathname'
require 'yaml'

module JavaBuildpack::Container::Wls

  class ServiceBindingsReader

    def self.createServiceDefinitionsFromFileSet(serviceBindingLocations, configRoot, outputPropsFile)

      serviceBindingLocations.each { |inputServiceBindingsLocation|


        parentPathName = Pathname.new(File.dirname(inputServiceBindingsLocation))
        moduleName = parentPathName.relative_path_from(configRoot).to_s.downcase

        inputServiceBindingsF = File.open(inputServiceBindingsLocation, 'r')
        serviceConfig = YAML.load_file(inputServiceBindingsF)

        serviceConfig.each { |serviceEntry|

          createServiceDefinitionsFromAppConfig(serviceEntry, moduleName, outputPropsFile)
        }

      }
    end


    def self.createServiceDefinitionsFromBindings(serviceConfig, outputPropsFile )

      serviceConfig.each { |serviceEntry|

        serviceType = serviceEntry["label"]

        print "-----> Processing Service Binding of type: #{serviceType} and definition : #{serviceEntry} \n"
        logger.debug {  "Processing Service Binding of type: #{serviceType} and definition : #{serviceEntry} " }

        if (serviceType[/cleardb/])

          mySqlConfig = serviceEntry

          createJdbcServiceDefinition(mySqlConfig, outputPropsFile)

        elsif (serviceType[/elephantsql/])

          postgresConfig = serviceEntry

          createJdbcServiceDefinition(postgresConfig, outputPropsFile)


        elsif (serviceType[/cloudamqp/])

          amqpConfig = serviceEntry

          saveAMQPJMSServiceDefinition(amqpConfig, outputPropsFile)


        elsif (serviceType[/user-provided/])

          userDefinedService = serviceEntry

          if userDefinedService.to_s[/jdbc/]

            # This appears to be of type JDBC
            createJdbcServiceDefinition(userDefinedService, outputPropsFile)

          elsif userDefinedService.to_s[/amqp/]

            # This appears to be of type AMQP
            saveAMQPJMSServiceDefinition(userDefinedService, outputPropsFile)

          else

            print "       Unknown User defined Service bindings !!!... #{userDefinedService.to_s}\n"
            logger.debug { "Unknown User defined Service bindings !!!... #{userDefinedService.to_s}" }

          end

        else

          print "       Unknown Service bindings !!!... #{serviceEntry.to_s}\n"
          logger.debug { "Unknown Service bindings !!!... #{serviceEntry.to_s}" }

        end

      }

    end


    def self.createServiceDefinitionsFromAppConfig(serviceConfig, moduleName, outputPropsFile )

      print "-----> Processing App bundled Service Definition : #{serviceConfig}\n"
      logger.debug {  "Processing App bundled Service Definition : #{serviceConfig}" }

      serviceName     = serviceConfig[0]
      subsystemConfig = serviceConfig[1]

      if ( moduleName == ".")


        # Directly save the Domain configuration
        saveBaseServiceDefinition(subsystemConfig, outputPropsFile, "Domain")

      elsif (moduleName[/jdbc/])

        # Directly save the jdbc configuration
        saveJdbcServiceDefinition(subsystemConfig, outputPropsFile)

      elsif  (moduleName[/^jms/])

        serviceName = "JMS-"+ serviceName if !serviceName[/^JMS/]

        # Directly save the JMS configuration
        saveBaseServiceDefinition(subsystemConfig, outputPropsFile, serviceName)

      elsif  (moduleName[/^foreign/])

        serviceName = "ForeignJMS-"+ serviceName if !serviceName[/^ForeignJMS/]

        # Directly save the Foreign JMS configuration
        saveBaseServiceDefinition(subsystemConfig, outputPropsFile, serviceName )

      elsif  (moduleName[/security/])


        # Directly save the Security configuration
        saveBaseServiceDefinition(subsystemConfig, outputPropsFile, "Security" )

      elsif  (moduleName[/jvm/])

        # Skip the JVM Configurations as the jvm wont be used by WLST for domain generation,
        # only used by buildpack for generating the scripts

      else

        print "       Unknown subsystem, just saving it : #{subsystemConfig}\n"
        logger.debug { "Unknown subsystem, just saving it : #{subsystemConfig}"}

        # Dont know what subsystem this relates to, just save it as Section matching its serviceName
        saveBaseServiceDefinition(subsystemConfig, outputPropsFile, serviceName)

      end

    end

    private

    JDBC_CONN_CREATION_RETRY_FREQ_SECS =900.freeze

    def self.createJdbcServiceDefinition(serviceEntry, outputPropsFile)

      #p "Processing JDBC service entry: #{serviceEntry}"

      jdbcDatasourceConfig             = serviceEntry['credentials']
      jdbcDatasourceConfig['name']     = serviceEntry['name']
      jdbcDatasourceConfig['jndiName'] = serviceEntry['name'] if jdbcDatasourceConfig['jndiName'].nil?

      saveJdbcServiceDefinition(jdbcDatasourceConfig, outputPropsFile)

    end

    def self.saveJdbcServiceDefinition(jdbcDatasourceConfig, outputPropsFile)


      sectionName = jdbcDatasourceConfig['name']
      sectionName = "JDBCDatasource-" + sectionName if !sectionName[/^JDBCDatasource/]

      logger.debug {  "Saving JDBC Datasource service defn : #{jdbcDatasourceConfig}" }

      File.open(outputPropsFile, 'a') do |f|
        f.puts ""
        f.puts "[#{sectionName}]"
        f.puts "name=#{jdbcDatasourceConfig['name']}"
        f.puts "jndiName=#{jdbcDatasourceConfig['jndiName']}"
        f.puts "username=#{jdbcDatasourceConfig['username']}" if !jdbcDatasourceConfig['username'].nil?
        f.puts "password=#{jdbcDatasourceConfig['password']}" if !jdbcDatasourceConfig['password'].nil?

        jdbcUrl = jdbcDatasourceConfig["jdbcUrl"]

        if (jdbcDatasourceConfig.to_s[/mysql/])
          f.puts "driver=com.mysql.jdbc.Driver"
          f.puts "testSql=SQL SELECT 1"

        elsif  (jdbcDatasourceConfig.to_s[/]postg/])
          f.puts "driver=org.postgresql.Driver"
          f.puts "testSql=SQL SELECT 1"

          # Check against postgres for jdbcUrl,
          # it only passes in uri rather than jdbcUrl

          jdbcUrl = ( "jdbc:" + jdbcDatasourceConfig["uri"] ) if jdbcUrl.nil?

        elsif (jdbcDatasourceConfig.to_s[/oracle/])

          f.puts "testSql=SQL SELECT 1 from DUAL"

          if jdbcDatasourceConfig['driver'].nil?
            f.puts "driver=oracle.jdbc.OracleDriver"
          else
            f.puts "driver=#{jdbcDatasourceConfig['driver']}"
          end

        end

        if ( (!jdbcDatasourceConfig['isMultiDS'].nil?) &&  (jdbcDatasourceConfig['isMultiDS'] ))
          f.puts "isMultiDS=true"
          f.puts "jdbcUrlPrefix=#{jdbcDatasourceConfig['jdbcUrlPrefix']}"
          f.puts "jdbcUrlEndpoints=#{jdbcDatasourceConfig['jdbcUrlEndpoints']}"
          f.puts "mp_algorithm=#{jdbcDatasourceConfig['mp_algorithm']}"
        else
          f.puts "isMultiDS=false"
          f.puts "jdbcUrl=#{jdbcUrl}"
        end

        initCapacity = 1
        initCapacity=jdbcDatasourceConfig['initCapacity'] if !jdbcDatasourceConfig['initCapacity'].nil?
        f.puts "initCapacity=#{initCapacity}"

        maxCapacity = 4
        maxCapacity=jdbcDatasourceConfig['maxCapacity'] if !jdbcDatasourceConfig['maxCapacity'].nil?
        f.puts "maxCapacity=#{maxCapacity}"

        xaProtocol='None'
        xaProtocol=jdbcDatasourceConfig['xaProtocol'] if (!jdbcDatasourceConfig['xaProtocol'].nil?)
        f.puts "xaProtocol=#{xaProtocol}"


        connectionCreationRetryFrequency = JDBC_CONN_CREATION_RETRY_FREQ_SECS
        connectionCreationRetryFrequency = jdbcDatasourceConfig['connectionCreationRetryFrequency'] if (!jdbcDatasourceConfig['connectionCreationRetryFrequency'].nil?)
        f.puts "connectionCreationRetryFrequency=#{connectionCreationRetryFrequency}"

        f.puts ""

      end

    end



    # Dont see a point of WLS customers using AMQP to communicate...
    def self.saveAMQPJMSServiceDefinition(amqpService, outputPropsFile)

      #logger.debug {  "Saving AMQP service defn : #{amqpService}" }

      # Dont know which InitialCF to use as well as the various arguments to pass in to bridge WLS To AMQP
      # Found some docs that talk of Apache ActiveMQ: org.apache.activemq.jndi.ActiveMQInitialContextFactory
      # and some others using: org.apache.qpid.amqp_1_0.jms.jndi.PropertiesFileInitialContextFactory

      File.open(outputPropsFile, 'a') do |f|
        f.puts ""
        f.puts "[ForeignJMS-AQMP-#{amqpService['name']}]"
        f.puts "name=#{amqpService['name']}"
        f.puts "jndiProperties=javax.naming.factory.initial=org.apache.qpid.amqp_1_0.jms.jndi.PropertiesFileInitialContextFactory;" + "javax.naming.provider.url=" + "#{amqpService['credentials']['uri']}" + "uri=#{amqpService['credentials']['uri']}"
        f.puts ""

      end


    end

    # Dont see a point of WLS customers using AMQP to communicate...
    def self.saveBaseServiceDefinition(serviceConfig, outputPropsFile, serviceName)


      #logger.debug { "Saving Service Defn : #{serviceConfig} with serviceName: #{serviceName}" }
      File.open(outputPropsFile, 'a') do |f|
        f.puts ""
        f.puts "[#{serviceName}]"

        serviceConfig.each { |entry|

            f.puts "#{entry[0]}=#{entry[1]}"

        }

        f.puts ""

      end

    end


      def self.logger
        JavaBuildpack::Logging::LoggerFactory.get_logger JavaBuildpack::Container::Weblogic
      end

  end


end
