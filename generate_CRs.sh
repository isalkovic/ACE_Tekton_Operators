# Env variables DEPLOYMENT_NAMESPACE, BAR_NAME , INTEGRATION_SERVER_NAME NEXUS_SERVER_BASE_URL, NEXUS_REPOSITORY_NAME ,NEXUS_PATH and BAR_VERSION are set in the pipeline/pipelinerun/task definitions

PathToConfigFolder=/workspace/output/initial-config

DIRbarauth=${PathToConfigFolder}/barauth
DIRsetdbparms=${PathToConfigFolder}/setdbparms
DIRtruststore=${PathToConfigFolder}/truststore
DIRpolicies=${PathToConfigFolder}/policies
DIRserverconf=${PathToConfigFolder}/serverconf
#DIRsetdbparms=server-config/initial-config/setdbparms

CRs_template_folder=/workspace/output/operator_resources_CRs
CRs_generated_folder=/workspace/output/operator_resources_CRs/generated

BARurl=${NEXUS_SERVER_BASE_URL}/repository/${NEXUS_REPOSITORY_NAME}/${NEXUS_PATH}/${BAR_VERSION}/${BAR_NAME}-${BAR_VERSION}.bar

mkdir ${CRs_generated_folder}
mkdir ${CRs_generated_folder}/configurations

# Create the Integration Server CR in any case
echo "Generating integration server CR yaml"
sed -e "s/replace-with-server-name/${INTEGRATION_SERVER_NAME}/" -e "s~replace-with-namespace~${DEPLOYMENT_NAMESPACE}~" -e "s~replace-With-Bar-URL~${BARurl}~" ${CRs_template_folder}/integrationServer.yaml > ${CRs_generated_folder}/integrationServer-generated.yaml
#!!!!!!!!!!!!!!!!
####### ADD ALSO A REFERENCE TO BAR FILE
#!!!!!!!!!!!!!!!!

# Create CR for bar auth - always set it, as it is always needed if external bar repo used
if [ -d "${DIRbarauth}" ]
then
	if [ "$(ls -A ${DIRbarauth})" ]; then
    echo "Generating bar auth CR yaml"
    barauth=$(base64 -w 0 ${DIRbarauth}/auth.json)
    sed -e "s/replace-with-namespace/${DEPLOYMENT_NAMESPACE}/" -e "s~replace-with-barauth-name~${BAR_NAME}-barauth~" -e "s~replace-with-barauth-base64~${barauth}~" ${CRs_template_folder}/configuration_barauth.yaml > ${CRs_generated_folder}/configurations/barauth-generated.yaml
    #add reference to this config cr to integration server cr
		echo "Adding barauth configuration reference to integration server CR yaml"
    echo "    - ${BAR_NAME}-barauth" >> ${CRs_generated_folder}/integrationServer-generated.yaml
	else
    echo "${DIRbarauth} is Empty. Skipping."
	fi
else
	echo "Directory ${DIRbarauth} not found. Skipping."
fi

# Create CR for setdbparms if folder exists and is not empty
if [ -d "${DIRsetdbparms}" ]
then
	if [ "$(ls -A ${DIRsetdbparms})" ]; then
    echo "Generating setdbparms CR yaml"
    setdbparms=$(base64 -w 0 ${DIRsetdbparms}/setdbparms.txt)
    sed -e "s/replace-with-namespace/${DEPLOYMENT_NAMESPACE}/" -e "s~replace-with-setdbparms-name~${BAR_NAME}-setdbparms~" -e "s~replace-with-setdbparms-base64~${setdbparms}~" ${CRs_template_folder}/configuration_setdbparms.yaml > ${CRs_generated_folder}/configurations/setdbparms-generated.yaml
    #add reference to this config cr to integration server cr
		echo "Adding setdbparms configuration reference to integration server CR yaml"
    echo "    - ${BAR_NAME}-setdbparms" >> ${CRs_generated_folder}/integrationServer-generated.yaml
	else
    echo "${DIRsetdbparms} is Empty. Skipping."
	fi
else
	echo "Directory ${DIRsetdbparms} not found. Skipping."
fi

# Create CR for truststore if folder exists and is not empty
if [ -d "${DIRtruststore}" ]
then
	if [ "$(ls -A ${DIRtruststore})" ]; then
    echo "Generating truststore CR yaml"
    truststore=$(base64 -w 0 server-config/initial-config/truststore/es-cert.p12)
    sed -e "s/replace-with-namespace/${DEPLOYMENT_NAMESPACE}/" -e "s~replace-with-truststore-name~${BAR_NAME}-truststore~" -e "s~replace-with-truststore-base64~${truststore}~" ${CRs_template_folder}/configuration_truststore.yaml > ${CRs_generated_folder}/configurations/truststore-generated.yaml
    #add reference to this config cr to integration server cr
		echo "Adding truststore configuration reference to integration server CR yaml"
    echo "    - ${BAR_NAME}-truststore" >> ${CRs_generated_folder}/integrationServer-generated.yaml
  else
    echo "${DIRtruststore} is Empty. Skipping."
	fi
else
	echo "Directory ${DIRtruststore} not found. Skipping."
fi

# If folder exists and not empty, Create CR for the policy project, zip policy files, exclude any old zip file and replace old zip file
if [ -d "${DIRpolicies}" ]
then
	if [ "$(ls -A ${DIRpolicies})" ]; then
    echo "Generating policy CR yaml"
		# alternative to zip - requires tar and compress:: tar -cZf ${PathToConfigFolder}/policy.zip -C ${DIRpolicies} .
    # works if you have zip installed::
		zip -r - ${DIRpolicies}/* > ${PathToConfigFolder}/policy.zip -x '*.zip*'
    policy=$(base64 -w 0 ${PathToConfigFolder}/policy.zip)
    sed -e "s/replace-with-namespace/${DEPLOYMENT_NAMESPACE}/" -e "s~replace-with-policy-name~${BAR_NAME}-policy~" -e "s~replace-with-policy-base64~${policy}~" ${CRs_template_folder}/configuration_policyProject.yaml > ${CRs_generated_folder}/configurations/policyProject-generated.yaml
    #add reference to this config cr to integration server cr
		echo "Adding policyProject configuration reference to integration server CR yaml"
    echo "    - ${BAR_NAME}-policy" >> ${CRs_generated_folder}/integrationServer-generated.yaml
else
    echo "${DIRpolicies} is Empty. Skipping."
	fi
else
	echo "Directory ${DIRpolicies} not found. Skipping."
fi

# Create CR for server configuration
if [ -d "${DIRserverconf}" ]
then
	if [ "$(ls -A ${DIRserverconf})" ]; then
    echo "Generating server conf CR yaml"
    serverconf=$(base64 -w 0 ${DIRserverconf}/server.conf.yaml)
    sed -e "s/replace-with-namespace/${DEPLOYMENT_NAMESPACE}/" -e "s~replace-with-serverconf-name~${BAR_NAME}-serverconf~" -e "s~replace-with-serverconf-base64~${serverconf}~" ${CRs_template_folder}/configuration_serverconf.yaml > ${CRs_generated_folder}/configurations/server.conf-generated.yaml
    #add reference to this config cr to integration server cr
		echo "Adding serverconf configuration reference to integration server CR yaml"
    echo "    - ${BAR_NAME}-serverconf" >> ${CRs_generated_folder}/integrationServer-generated.yaml
else
    echo "${DIRserverconf} is Empty. Skipping."
	fi
else
	echo "Directory ${DIRserverconf} not found. Skipping."
fi
