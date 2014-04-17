####################################
# Base WLS Domain Creation script  #
####################################

from jarray import array
from java.io import File
from sets import Set
from java.io import FileInputStream
from java.util import Properties
from java.lang import Exception
import re
import ConfigParser




def getConfigSectionMap(config, section):
    dict1 = {}
    options = config.options(section)

    listedOptions = ''
    for option in options:
        listedOptions += option + ' '
        try:
            dict1[option] = config.get(section, option)
            if dict1[option] == -1:
                DebugPrint("skip: %s" % option)
        except:
            print("exception on %s!" % option)
            dict1[option] = None
    print 'Section['+section+'] > props : ' + listedOptions
    return dict1

def loadGlobalProp(domainConfig):
   global WL_HOME, SERVER_NAME, DOMAIN, DOMAIN_PATH, DOMAIN_NAME

   WL_HOME     = str(domainConfig.get('wlsHome'))
   DOMAIN_PATH = str(domainConfig.get('domainPath'))

   SERVER_NAME = 'myserver'
   DOMAIN_NAME = 'cfDomain'

   if 'serverName' in domainConfig:
    SERVER_NAME = str(domainConfig.get('serverName'))

   if 'domainName' in domainConfig:
      DOMAIN_NAME = str(domainConfig.get('domainName'))

   DOMAIN      = DOMAIN_PATH + '/' + DOMAIN_NAME


def usage():
  print "Need to pass properties file as argument to script!!"
  exit(-1)





#===============================================================================
# Sample code referenced from Oracle WLS Portal documentation:
# http://docs.oracle.com/cd/E13218_01/wlp/docs92/db/appx_oracle_rac_scripts.html
#===============================================================================

def createPhysicalDataSource(datasourceConfig, targetServer, dsName, jndiName, jdbcUrl):
  print 'Creating PhysicalDatasource for ds: ' + dsName + ' with config: ' + str(datasourceConfig)

  try:
    username      = datasourceConfig.get('username')
    password      = datasourceConfig.get('password')
    xaProtocol    = datasourceConfig.get('xaProtocol')

    initCapacity  = int(datasourceConfig.get('initCapacity'))
    maxCapacity   = int(datasourceConfig.get('maxCapacity'))
    driver        = datasourceConfig.get('driver')
    testSql       = datasourceConfig.get('testSql')
    connRetryFreq = int(datasourceConfig.get('connectionCreationRetryFrequency'))

    cd('/')

    sysRes = create(dsName, "JDBCSystemResource")
    assign('JDBCSystemResource', dsName, 'Target', targetServer)

    cd('/JDBCSystemResource/' + dsName + '/JdbcResource/' + dsName)
    dataSourceParams=create('dataSourceParams','JDBCDataSourceParams')
    dataSourceParams.setGlobalTransactionsProtocol(xaProtocol)
    cd('JDBCDataSourceParams/NO_NAME_0')
    set('JNDIName',jndiName)

    cd('/JDBCSystemResource/' + dsName + '/JdbcResource/' + dsName)
    connPoolParams=create('connPoolParams','JDBCConnectionPoolParams')
    connPoolParams.setMaxCapacity(int(maxCapacity))
    connPoolParams.setInitialCapacity(int(initCapacity))

    connPoolParams.setTestConnectionsOnReserve(true)
    connPoolParams.setTestTableName(testSql)
    connPoolParams.setSecondsToTrustAnIdlePoolConnection(20)

    # Edit the connection recreation freq time if 300 seconds/5 mins is too long
    connPoolParams.setConnectionCreationRetryFrequencySeconds(connRetryFreq)

    # Uncomment for leak detection and tweak the timeout period according to appln needs
    #connPoolParams.setInactiveConnectionTimeoutSeconds(200)

    capacityIncrementMultiples = int((maxCapacity - initCapacity) % 10)
    if (capacityIncrementMultiples < 0):
       connPoolParams.setCapacityIncrement(1)
    elif (capacityIncrementMultiples > 3):
       connPoolParams.setCapacityIncrement(5)
    else:
       connPoolParams.setCapacityIncrement(3)

    cd('/JDBCSystemResource/' + dsName + '/JdbcResource/' + dsName)
    driverParams=create('driverParams','JDBCDriverParams')
    driverParams.setUrl(jdbcUrl)
    driverParams.setDriverName(driver)
    driverParams.setPasswordEncrypted(password)
    cd('JDBCDriverParams/NO_NAME_0')
    create(dsName,'Properties')
    cd('Properties/NO_NAME_0')
    create('user', 'Property')
    cd('Property/user')
    cmo.setValue(username)

    if xaProtocol != "None":
      cd('/JDBCSystemResource/' + dsName + '/JdbcResource/' + dsName)
      XAParams=create('XAParams','JDBCXAParams')
      XAParams.setKeepXaConnTillTxComplete(true)
      XAParams.setXaRetryDurationSeconds(300)
      XAParams.setXaTransactionTimeout(0)
      XAParams.setXaSetTransactionTimeout(true)
      XAParams.setXaEndOnlyOnce(true)

    print 'PhysicalDataSource ' + dsName + ' successfully created.'
  except ConfigParser.NoOptionError, err:
      print str(err)
  except:
    dumpStack()

def createMultiDataSource(datasourceConfig, targetServer):
  try:
    dsName   = datasourceConfig.get('name')
    print 'Creating MDS for ds: ' + dsName + ' with config: ' + str(datasourceConfig)

    jndiName         = datasourceConfig.get('jndiName')
    mp_algorithm     = datasourceConfig.get('mp_algorithm')
    jdbcUrlPrefix    = datasourceConfig.get('jdbcUrlPrefix')
    jdbcUrlEndpoints = datasourceConfig.get('jdbcUrlEndpoints')
    xaProtocol       = datasourceConfig.get('xaProtocol')

    jdbcUrlEndpointEntries = jdbcUrlEndpoints.split('|')
    print 'Got jdbcUrlEndpoints : ' + str(jdbcUrlEndpointEntries)

    ds_list = ''
    index = 0
    for jdbcUrlEndpoint in (jdbcUrlEndpointEntries):
      index += 1
      createPhysicalDataSource(datasourceConfig, targetServer, ('Physical-' + dsName + '-' + str(index)), jndiName + '-' + str(index), jdbcUrlPrefix + ":@" + jdbcUrlEndpoint)
      if (index > 1):
        ds_list = ds_list + ','
      ds_list = ds_list + ('Physical-' + dsName + '-' + str(index))

    cd('/')
    sysRes = create(dsName, "JDBCSystemResource")
    assign('JDBCSystemResource', dsName, 'Target', targetServer)

    cd('/JDBCSystemResource/' + dsName + '/JdbcResource/' + dsName)
    dataSourceParams=create('dataSourceParams','JDBCDataSourceParams')
    dataSourceParams.setAlgorithmType(mp_algorithm)
    dataSourceParams.setDataSourceList(ds_list)

    cd('JDBCDataSourceParams/NO_NAME_0')
    set('JNDIName',jndiName)
    set('GlobalTransactionsProtocol', xaProtocol)

    print 'Multi DataSource '+ dsName + ' successfully created.'
  except ConfigParser.NoOptionError, err:
        print str(err)
  except:
    dumpStack()

def createDataSource(datasourceConfig, targetServer):
 try:
  useMultiDS = datasourceConfig.get('isMultiDS')
  dsName   = datasourceConfig.get('name')

  if (useMultiDS == "true"):
    #This is a multidatasource or RAC configuration
    createMultiDataSource(datasourceConfig, targetServer)
    print 'Done Creating Multipool DataSource : ' + dsName
  else:
    jdbcUrl  = datasourceConfig.get('jdbcUrl')
    jndiName = datasourceConfig.get('jndiName')
    createPhysicalDataSource(datasourceConfig, targetServer, dsName, jndiName, jdbcUrl)
    print 'Done Creating Physical DataSource : ' + dsName

 except ConfigParser.NoOptionError, err:
       print str(err)
 except:
  dumpStack()



#==========================================
# Create JMS Artifacts.
#==========================================


# There is going to only one server per install, no support for clusters...
def createForeignJMSResources(foreignJmsConfig, targetServer):
 try:

  cd('/')
  jmsForeignServer = foreignJmsConfig.get('name')
  foreignJmsModuleName = jmsForeignServer + "Module"

  jmsModule = create(foreignJmsModuleName, 'JMSSystemResource')
  assign('JMSSystemResource', foreignJmsModuleName, 'Target', targetServer)
  cd('JMSSystemResource/'+foreignJmsModuleName)

  #subDeployment = jmsModuleName + 'subDeployment'
  #create(subDeployment, 'SubDeployment')
  #assign('JMSSystemResource.SubDeployment', subDeployment, 'Target', jmsServer)


  cd('JmsResource/NO_NAME_0')
  foreignJmsServer = create(jmsForeignServer, 'ForeignServer')
  cd('ForeignServer/'+jmsForeignServer)
  foreignJmsServer.setDefaultTargetingEnabled(true)

  #set('ConnectionURL', url)
  #set('JNDIPropertiesCredentialEncrypted')


  if 'jndiProperties' in foreignJmsConfig:
        jndiPropertyPairs = foreignJmsConfig.get('jndiProperties').split(';')
        print 'JNDI PropertyPairs : ' + str(jndiPropertyPairs)
        index = 0
        for jndiPropertyPair in (jndiPropertyPairs):
            print 'JNDI PropertyPair : ' + str(jndiPropertyPair)
            namevalue = jndiPropertyPair.split('=')
            propName  = namevalue[0]
            propValue = namevalue[1]

            create(propName, 'JNDIProperty')
            cd('JNDIProperty/NO_NAME_' + str(index))
            set('Key', propName)
            set('Value', propValue)
            cd('../..')
            index += 1

  print 'Created Foreign JMS Server ', jmsForeignServer , ' and updated its jndi properties'
  pwd()

  if ('cfs' in foreignJmsConfig):
    cfNames = foreignJmsConfig.get('cfs')
    for entry in (cfNames.split(';')):
        paths = entry.split('/')
        baseName = paths[len(paths) - 1 ] + "CF"

        resource = create(baseName, 'ForeignConnectionFactory')
        jndiNamePair = entry.split('|')
        localJndiName  = jndiNamePair[0]
        remoteJndiName = jndiNamePair[1]

        cd ('ForeignConnectionFactories/' + baseName)
        resource.setLocalJNDIName(localJndiName)
        resource.setRemoteJNDIName(remoteJndiName)
        cd ('../..')
        print 'Created Foreign CF for : ' + baseName

  if ('destinations' in foreignJmsConfig):
    destNames = foreignJmsConfig.get('destinations')
    for entry in (destNames.split(';')):
        paths = entry.split('/')
        baseName = paths[len(paths) - 1 ] + "Destn"

        resource = create(baseName, 'ForeignDestination')
        jndiNamePair = entry.split('|')
        localJndiName  = jndiNamePair[0]
        remoteJndiName = jndiNamePair[1]

        cd ('ForeignDestinations/' + baseName)
        resource.setLocalJNDIName(localJndiName)
        resource.setRemoteJNDIName(remoteJndiName)
        cd ('../..')
        print 'Created Foreign Destination for : ' + baseName

 except:
  dumpStack()

def createJMSServer(jmsServerName, targetServer):
  cd('/')
  create(jmsServerName, 'JMSServer')
  assign('JMSServer', jmsServerName, 'Target', targetServer)
  print 'Created JMSServer : ', jmsServerName
  print '    Warning!!!, not creating any associated stores with the jms server'


# There is going to only one server per install, no support for clusters...
def createJMSModules(jmsConfig, jmsServer, targetServer):
 try:

  cd('/')
  jmsModuleName = jmsConfig.get('moduleName')
  subDeployment = jmsModuleName + 'subDeployment'

  jmsModule = create(jmsModuleName, 'JMSSystemResource')
  assign('JMSSystemResource', jmsModuleName, 'Target', targetServer)
  cd('JMSSystemResource/'+jmsModuleName)
  create(subDeployment, 'SubDeployment')
  assign('JMSSystemResource.SubDeployment', subDeployment, 'Target', jmsServer)

  print 'Created JMSModule: ', jmsModuleName

  cd('JmsResource/NO_NAME_0')

  if ('nonXaCfs' in jmsConfig):
    nonXaCfNames = jmsConfig.get('nonXaCfs')
    for nonXaCf in (nonXaCfNames.split(';')):
        cfPaths = nonXaCf.split('/')
        baseCfName = cfPaths[len(cfPaths) - 1 ]

        cf = create(baseCfName, 'ConnectionFactory')
        cf.setJNDIName(nonXaCf)
        cf.setDefaultTargetingEnabled(true)
        print 'Created CF for : ' + nonXaCf

  if ('xaCfs' in jmsConfig):
      xaCfNames = jmsConfig.get('xaCfs')
      for xaCf in (xaCfNames.split(';')):
        cfPaths = xaCf.split('/')
        baseCfName = cfPaths[len(cfPaths) - 1 ]

        cf = create(baseCfName, 'ConnectionFactory')
        cf.setJNDIName(xaCf)
        cf.setDefaultTargetingEnabled(true)
        print 'Created CF for : ' + xaCf

        cd('ConnectionFactory/' + baseCfName)
        tp=create(baseCfName, 'TransactionParams')
        cd('TransactionParams/NO_NAME_0')
        tp.setXAConnectionFactoryEnabled(true)
        cd('../../../..')

  if ('queues' in jmsConfig):
      queueNames = jmsConfig.get('queues')
      queueNameArr = queueNames.split(';')
      for queueName in (queueNameArr):
        queuePaths = queueName.split('/')
        baseQueueName = queuePaths[len(queuePaths) - 1]
        queue = create(baseQueueName, 'Queue')
        queue.setJNDIName(queueName)
        queue.setSubDeploymentName(subDeployment)
        print ' Created Queue: ' + baseQueueName + ' with jndi: ' + queueName

  if ('topics' in jmsConfig):
      topicNames = jmsConfig.get('topics')
      topicNameArr = topicNames.split(';')
      for topicName in (topicNameArr):
        topicPaths = topicName.split('/')
        baseTopicName = topicPaths[len(topicPaths) - 1]
        topic = create(baseTopicName, 'Topic')
        topic.setJNDIName(topicName)
        topic.setSubDeploymentName(subDeployment)
        print ' Created Topic: ' + baseTopicName + ' with jndi: ' + topicName
 except:
  dumpStack()

def createJmsConfig(jmsConfig, targetServer):
  jmsServerName = jmsConfig.get('jmsServer')
  createJMSServer(jmsServerName, targetServer)
  createJMSModules(jmsConfig, jmsServerName, targetServer)

#==========================================
# Deploy Apps
#==========================================

def deployApp(appName, appSrcPath, targetServer):
 try:
  cd('/')

  app = create(appName, 'AppDeployment')
  cd('/AppDeployment/'+appName)
  set('SourcePath', appSrcPath )
  set('Target', targetServer)
  print 'Deployed ' + appName + ' with source path: ' + appSrcPath + ' to ' + targetServer
 except:
  dumpStack()


#==========================================
# Create a domain from the weblogic domain template.
#==========================================
def createDomain(domainEnvConfig):
  baseWLSTemplate = WL_HOME +'/common/templates/wls/wls.jar'
  print 'Reading WLS template from : ' + baseWLSTemplate
  readTemplate(baseWLSTemplate)
  cd('Servers/AdminServer')

  # Configure the Administration Server
  # The Listen Port would be passed as java command line arg dependent on env variable $PORT { -Dweblogic.ListenPort=$PORT }
  #set('ListenPort', int(domainEnvConfig.get('serverPort')))
  set('Name', SERVER_NAME)

  log=create(SERVER_NAME, 'Log')
  cd('Log/'+SERVER_NAME)
  set('StdoutSeverity', 'Debug')
  set('LoggerSeverity', 'Debug')
  set('RedirectStdoutToServerLogEnabled', 'true')

  cd('/')
  cd('Security/base_domain/User/weblogic')

  if 'wlsUser' in domainEnvConfig:
    set('Name', domainEnvConfig.get('wlsUser'))

  if 'wlsPasswd' in domainEnvConfig:
    cmo.setPassword(domainEnvConfig.get('wlsPasswd'))
  else:
    cmo.setPassword('welcome1')


  cd('/')
  if 'consoleEnabled' in domainEnvConfig:
    set('ConsoleEnabled', domainEnvConfig.get('consoleEnabled'))
  if 'prodModeEnabled' in domainEnvConfig:
    set('ProductionModeEnabled', domainEnvConfig.get('prodModeEnabled'))

  setOption('OverwriteDomain', 'true')
  writeDomain(DOMAIN)
  closeTemplate()
  closeDomain()
  print 'Created Domain : ' + DOMAIN

def configureDomain(domainConfigProps):
 try:
  print 'Reading domain : ' , DOMAIN
  readDomain(DOMAIN)

  cd('/')

  targetServer = SERVER_NAME

  for sectionName in domainConfigProps.sections():
    print '\nHandling Section: ', sectionName
    if (sectionName.startswith("JDBC")):

      datasourceConfig = getConfigSectionMap(domainConfigProps, sectionName)
      createDataSource(datasourceConfig, targetServer)

    elif (sectionName.startswith("JMS")):
      jmsConfig = getConfigSectionMap(domainConfigProps, sectionName)
      createJmsConfig(jmsConfig, targetServer)

    elif (sectionName.startswith("Foreign")):
      foreignJmsConfig = getConfigSectionMap(domainConfigProps, sectionName)
      createForeignJMSResources(foreignJmsConfig, targetServer)

  appName = domainEnvConfig.get('appName')
  appSrcPath = domainEnvConfig.get('appSrcPath')
  deployApp(appName, appSrcPath, targetServer)

  updateDomain()
  closeDomain()
 except ConfigParser.NoOptionError, err:
       print str(err)
 except:
  dumpStack()


try:
  if (len(sys.argv) < 1):
    Usage()


  propFile = sys.argv[1]
  domainConfigProps = ConfigParser.ConfigParser()
  domainConfigProps.optionxform = str
  domainConfigProps.read(propFile)

  domainEnvConfig = getConfigSectionMap(domainConfigProps, 'Domain')
  loadGlobalProp(domainEnvConfig)
  createDomain(domainEnvConfig)
  configureDomain(domainConfigProps)



finally:
  dumpStack()
  print 'Done'
  exit
