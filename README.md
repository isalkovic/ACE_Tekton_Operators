# IBM App Connect Enterprise - Build and deploy using Git, Nexus, Tekton and ACE Operator

## Purpose of the document
This document describes detailed steps on how to set up an Openshift tekton pipeline and required environment, which will:
1. Push ACE code and configuration from the ACE toolkit to the Git repository
2. Start an Openshift pipelines (Tekton) pepeline
3. Clone a Git repository containing ACE code and ACE configuration
4. Build the ACE code to a BAR file
5. Upload the BAR file to a Nexus repository
6. Generate Custom Resources YAML files for ACE confguration and ACE integration server, which are used by the ACE Operator in the next steps
7. Apply Custom Resource files to the Openshift cluster
8. ACE Operator picks up the ACE configuration CRs and creates appropriate configuration and related Openshift resources (secrets, config maps,...)
9. ACE Operator picks up the ACE integration server CR and creates ACE server and related Openshift resources (deployment, service, routes,...)

![ACE pipeline](https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/ACE_Tekton_Pipeline.drawio.png?raw=true)

This document is a (functional) work in progress and will be improved along with the code which is located here: https://github.com/isalkovic/ACE_Tekton_Operators

Ideas for improvement:
- support more configuration types
- differentiate new deployment from update
- add option to deploy from custom image build (vs standard Operator deployment with BAR+ standard ACE image)


## Steps to configure the environment

1. We will start by creating a new Openshift project. The idea is to use a fresh/clean one, so that there is no interference with other existing projects and in this way all required resource dependencies are documented. Creating a new project is optional, but in that case you need to be aware that some steps may not be needed on your cluster.
In Openshift, create a new project with the name of your choice. In further instructions, we will reference it as $PROJECT . When performing further steps, always make sure you are in your $PROJECT, either in the Openshift console or in the command line.

2. Next prerequisite is to have Openshift Pipelines installed on our cluster.
In the Openshift console, go to Operators->Operator hub and search "Red Hat Openshift Pipelines" - when you find it, click on it, and install the Openshift Pipelines Operator.  

![RH Openshift pipelines Operator](https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/Red%20Hat%20OpenShift%20Pipelines.png?raw=true)  

This action will add a new section in your Openshift console - "Pipelines" will appear in the menu to the left.  

![RH Openshift pipelines menu](https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/Pipelines-menu.png?raw=true)

3. Since we will be using Nexus to store the BAR files that we build - we also need to install and configure Nexus. We will start by installing the "Nexus Repository Operator", which can be found again in the Operators->Operator hub - search for the "Nexus Repository Operator", click on it and install it in your $PROJECT .

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/Nexus%20Repository%20Operator.png?raw=true" width="300">  

4. After installing the Nexus Operator, we need to also create a new Nexus instance, using this operator. In the Openshift console, go to Operators->Installed operators and click on the Nexus Repository Operator.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/NR%20NexusRepo.png?raw=true" width="300">

On the "NexusRepo" tab, click the button "Create NexusRepo". Change the name if you like and click “Create” to create a new instance of Nexus repository.

5. Since we want to access our Nexus repository from outside the cluster, we need to expose it, using a route . In the Openshift console, go to Networking->Routes and click on the "Create route" button . Give this route a name of your choice, select the nexus service under “Service” and select the only available Target port (should be 8081) . Click the “Create” button to create a new route.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/nexus-route.png?raw=true" width="600">

On the next screen you will see the details of the new route. Under location, make a note of the Nexus route URL - we will reference it as $NEXUSURL - you will need it later. Also, click on this URL to open it in your browser and to test that the Nexus repo is up and running and available. If the Nexus repository is started successfully (it may take a couple of minutes), the Nexus UI will appear. In the top-right corner, click the button to sign-in to Nexus using default credentials ( admin / admin123 ) -> default wizard starts - click to allow anonymous access to the repo.  

6. Next, we must create a new Nexus repository, where we will be storing the BAR files. In Nexus UI, Go to settings->Repository->Repositories and click on the “Create repository” button.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/Nexus-newRepo.png?raw=true" width="600">

Select "maven2(hosted)" as type and proceed to give your repo a name - we will reference it as $NEXUSREPOSITORY.
Under Hosted->"Deployment policy" change default to “Allow redeploy”. This will make it easier to run the demo - you will be allowed to upload the same bar more than once (which can happen if you do not change the code between builds/deploys). Also, set the “Layout policy” to “Permissive” - this will make Nexus more flexible towards the path that you choose for the upload of your bar file - for demo it is fine like this.
On the bottom, click the “Create Repository” button.

7. Before proceeding to create the pipeline and pipeline elements, first you will need to define a Persistent Volume Claim (PVC) on your Openshift cluster. PVC is required by the pipeline, since this pipeline needs to exchange data between different pipeline Tasks - i.e. after you clone the repository and it’s files, they are later used in another Task to build the .bar file). To do this, we need persistent storage, since each pipeline Task runs as a separate container instance and as such is ephemeral.  Make sure that you are in the project which you have created earlier - $PROJECT. 
In the Openshift console, go to Storage->PersistentVolumeClaims and click on the button “Create PersistentVolumeClaim”. Select appropriate storage class, for size put 1GiB and give it a name of your choice - we will reference it as $PVCNAME - while leaving other parameters default.  
 Click the button “Create” and make sure that the status of your PVC is “Bound”.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/PVC.png?raw=true" width="600">

8. As a next step, you will clone the Git repository, which contains code example, configuration example and pipeline definitions - mostly because of the pipelines, which you need to modify and apply on the Openshift cluster. For this you will need the git CLI. 
In your command prompt, enter:   
```
git clone https://github.com/isalkovic/ACE_Tekton_Operators.git 
```

9. Another requirement of the pipeline (ace-build-bar Task) is to have an appropriate container image, which is suitable to run “ibm int” commands, which we need to execute in order to build the code generated in ACE Toolkit. We want this image to be as small and light as possible, but IBM does not provide such an image, so we need to build it. To build this light image, I have used some resources provided by Trevor Dolby, IBM ACE Architect.  
OK, so how will we do this? Start from the git repository which you have cloned in the previous step. Inside, there is a folder named "ace-minimal-image".  
Using this Dockerfile.aceminimalubuntu dockerfile build a new image (for this you will need to have either docker or alternative CLI installed on your machine):  
```
 docker build -t ace-with-zip -f Dockerfile.aceminimalubuntu .
```
  After building the image, tag it with appropriate tag, so that you can push the image to your Openshift image registry:  
```
 docker tag acewithzip $IMAGEREPOSITORY/$PROJECT/ace-with-zip:latest  
```
  Next, we need to tag and push our image to the internal Openshift registry.  

  First, we need to make sure that the registry is exposed and that we know it’s exposed address.  You can check if your registry is exposed if there is a registry route in the project openshift-image-registry. Make a note of that route and we will continue to reference it as $IMAGEREPOSITORY     
If your Openshift registry is not exposed, you first have to expose it using the following oc command:  
```
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge  
```  
Again, make a note of the new route which was created. In case of issues with docker login and self-signed certificate, a quick workaround could be to use podman instead of docker as described here: https://sgitario.github.io/docker-push-registry-unsecure  
 Next,  you need to login to your Openshift registry:
```
docker login -u openshift -p $(oc whoami -t) $IMAGEREPOSITORY  
```
And finally, push the image to the registry:  
```
docker push $IMAGEREPOSITORY/$PROJECT/ace-with-zip:latest  
```
CHEAT SHEET FOR PODMAN ALTERNATIVE::  
```
podman login -u openshift -p $(oc whoami -t) --tls-verify=false $IMAGEREPOSITORY  
podman build -t ace-with-zip -f Dockerfile.aceminimalubuntu .  
podman tag ace-with-zip $IMAGEREPOSITORY/$PROJECT/ace-with-zip:latest  
podman push --tls-verify=false $IMAGEREPOSITORY/$PROJECT/ace-with-zip:latest 
```
10. After you have cloned the repository, navigate to “pipeline” directory of this repository. You will need to do some modifications to pipeline elements definitions, in order for the pipeline to run successfully on your cluster. At minimal, do the following modifications:

| File name | Changes to be made |
| ----------------------------- | ----------- |
| pipeline-ace-build-and-deploy.yaml	 | Modify the default value of parameter “deployment-namespace” to match the name of your Openshift $PROJECT. Modify the default value of parameter “nexus-repository-name” to match the name of your Openshift $NEXUSREPOSITORY. Find parameter “nexus-server-base-url” and modify it to the Nexus base URL of your Nexus instance. Normally, this should be the $NEXUSURL URL which is the URL of your Nexus route, which you noted earlier. |
| pipelinerun-ace-build-and-deploy-run.yaml | Only in the case that you decided to change the name of the Persistent Volume Claim (PVC) , which you have created earlier, make a change to spec.workspaces.persistentVolumeClaim.claimName parameter, to match the name you have chosen. |  
| task-ace-build-bar.yaml | Update the spec.steps.image parameter, to be pointing to your ace image which you have built previously - so correct repository address, project and image name and tag. |
| task-ace-deploy-crs.yaml | N/A |
| task-ace-generate-crs.yaml | Update the spec.steps.image parameter, to be pointing to your ace image which you have built previously - so correct repository address, project and image name and tag. The only reason why here we are using the same image link for ace build is because in this step we need zip command, which I have packed in the same image. This should be improved. |
| task-ace-nexus-upload-bar.yaml | N/A |
| task-git-clone.yaml	 | N/A |

11. After you have made the appropriate changes, proceed with applying these pipeline definitions (yaml files) to your Openshift cluster.  
In the command prompt, enter (you will need to have oc CLI installed before you can do this):  
oc login yourClusterDetails (in the top-right corner of the Openshift console, click on your username and after that click of the “Copy login command” in the menu.  

  <img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/oclogincmd.png?raw=true" width="300">   

This will take you to a new browser tab, where you need to click display token and from there copy the “oc login …” command, which is specific for your user and your cluster.)
```  
oc project $PROJECT (first, you need to switch to your OCP project)  
oc apply -f pipelineElementName.yaml
```
where you change the name of the file, for each of the files in the pipeline directory.  

  As an alternative to running oc commands, you can do the same thing through the Openshift console. In the top-right corner of the console UI, click on the “+” (import YAML) button, and paste the contents of the yaml file.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/ocimportyaml.png?raw=true" width="300">

Click “Create” button to apply the pipeline element. Do this for all the files in the pipeline directory.

## Test your work - start the pipeline
Finally you have set-up your environment and we can start running some ACE pipelines, and hopefully even containers. To start your first pipeline, in the Openshift console go to Pipelines->Pipelines->PipelineRuns and click on the three dots next to your ace-build-and-deploy-pipeline-run pipeline run.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/pipeline-run.png?raw=true" width="800">  

 Click "Rerun", cross your fingers and hope that everything was set up correctly.

If you would like, you can track the execution of your pipeline (steps progression and step logs) by clicking on the name of your new pipeline run (it should be in “Running” status).  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/pipeline-logs.png?raw=true" width="800">  

If the pipeline was successful, you should see a completely green “Task status” for this pipeline run.  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/pipeline-success.png?raw=true" width="800">  

Once successfully completed, you can check if the sample app which was deployed is running and available.
To do this, on the Openshift console (make sure you are in your project) , go to Networking->Routes and find the route “Location” of your ACE server ( hint: it will have the name of the server which you have configured when editing the pipeline-ace-build-and-deploy.yaml pipeline file ). Open the URL in your browser and add the “/ExampleServer” path at the end.
If the ACE application is started and listening to requests, you should see the following message (exact view depends on your browser):  

<img src="https://github.com/isalkovic/ACE_Tekton_Operators-documentation/blob/main/images/testaceapp.png?raw=true" width="800">

## Congratulations!! You have successfully deployed your App Connec Enterprise application using these instructions :-)
