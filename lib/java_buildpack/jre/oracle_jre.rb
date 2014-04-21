# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013 the original author or authors.
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

require 'fileutils'
require 'java_buildpack/jre'
require 'java_buildpack/jre/open_jdk_like'

module JavaBuildpack::Jre

  # Encapsulates the detect, compile, and release functionality for selecting an Oracle JRE.
  class OracleJRE < OpenJDKLike

    # Expect to see a '.wls' folder containing domain configurations and script to create the domain within the App bits
    APP_WLS_CONFIG_CACHE_DIR       = '.wls'.freeze

    def supports?
      true

      #searchPath = (@application.root).to_s + "/**/weblogic*xml"
      #wlsConfigPresent = Dir.glob(searchPath).length > 0
      #((@application.root + APP_WLS_CONFIG_CACHE_DIR).exist? || wlsConfigPresent)
    end

  end

end
