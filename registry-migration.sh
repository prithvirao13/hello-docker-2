#!/bin/bash

error_exit()
{

# ----------------------------------------------------------------
# Function for exit due to fatal program error
#   Accepts 1 argument:
#     string containing descriptive error message
# ----------------------------------------------------------------


  echo "${1:-"Unknown Error"}" 1>&2
  exit 1
}

srcreg=$1 #"cr.[regionId].aliyuncs.com"
tgtreg=$2 #"awsacctnum.dkr.ecr.awsregion.amazonaws.com"

#repos=`curl -s http://$srcreg/v2/_catalog?n=2048 | jq '.repositories[]' | tr -d '"'`
repos=$(curl -s http://$srcreg/?Action=ListRepository&InstanceId=cri-kmsiwlxxdcvaduwb&RegionId=cn-shanghai)

for k in $(echo ${repos} | jq '.Repositories | keys | .[]'); do
   value=$(echo ${repos} | jq -r ".Repositories[$k]");
   repo=$(jq -r '.RepoName' <<< "$value");
   id=$(jq -r '.RepoId' <<< "$value");
   echo -e "\n===WORKING ON REPOSITORY" $repo"==="

   #check for existing repo at ECR and create if not exist
   echo -e "\n===CHECKING IF REPOSITORY EXISTS AT" $tgtreg"==="

   awsrepo=`aws ecr describe-repositories | grep -o \"$repo\" | tr -d '"'`
   if [ "$awsrepo" != "$repo" ]; then 
      echo -e "\n===CREATING REPOSITORY AT" $tgtreg"==="
      aws ecr create-repository --repository-name $repo || error_exit "$LINENO: An error has occurred."; 
   fi

   #tags=`curl -s http://$srcreg/v2/$repo/tags/list?n=2048 | jq '.tags[]' | tr -d '"'`
   tags=$(curl -s http://$srcreg/?Action=ListRepoTag&InstanceId=cri-kmsiwlxxdcvaduwb&RegionId=cn-shanghai&RepoId=$id | jq -r '.Images | .[].Tag')

      #check for existing tags at ECR and push if not exist
      for tag in $tags; do
         awstag=`aws ecr list-images --repository-name $repo | grep -o \"$tag\" | tr -d '"'`
         echo -e "\n===WORKING ON" $repo:$tag"==="

         if [ "$awstag" != "$tag" ]; then
            echo -e "\n===PULLING==="
            docker pull $srcreg/$repo:$tag || error_exit "$LINENO: An error has occurred."

            echo -e "\n===RETAGGING==="
            docker tag $srcreg/$repo:$tag $tgtreg/$repo:$tag || error_exit "$LINENO: An error has occurred."
            echo $srcreg/$repo:$tag "retagged to" $tgtreg/$repo:$tag

            echo -e "\n===PUSHING==="
            docker push $tgtreg/$repo:$tag || error_exit "$LINENO: An error has occurred."
         fi

      done

   #check local images and cleanup if necessary
   cleanup=`docker images -a | grep "$repo "`
   if [ "$cleanup" != "" ]; then
      echo -e "\n===CLEANING UP==="
      #add -f at end of the command below to force cleanup of matching repository images on local disk.
      #this may result in extra network traffic and longer migration times if you have inter-repo dependencies.
      #especially useful if disk space is a factor - only the working repo is retained on disk.
      docker images -a | grep $repo | awk '{print $3}' | xargs docker rmi
   fi

done