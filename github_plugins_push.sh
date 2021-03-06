#!/bin/bash

cd $(dirname $0)/../

for i in plugins/redmine_* public/themes/ministere p/redmine_*; do
  cd $i >/dev/null
  echo $i |tr 'a-z' 'A-Z'
  git status |grep ahead >/dev/null && \
    git config --get remote.origin.url |grep jbbarth >/dev/null && \
    git push origin master
  cd - >/dev/null
done
