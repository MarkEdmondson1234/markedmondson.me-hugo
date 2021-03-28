#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
RScript -e 'blogdown::build_site()'

# Copy all over to other GitHub repo that holds public files
cp -a public/. ../MarkEdmondson1234.github.io/

# Add changes to git.
cd ../MarkEdmondson1234.github.io/ && git add -A

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

#git remote set-url origin git@github.com:MarkEdmondson1234/MarkEdmondson1234.github.io.git

# Push source and build repos.
git push origin master

# Come Back
cd ../markedmondson.me-hugo