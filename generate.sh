#!/bin/bash

# Use this script to generate a pipeline for getting started
# guides. Clone the repository, and all the guides you want to build,
# in the same root directory. Then run this script to generate a
# pipeline.yml.

output=pipeline.yml;
mavens=();
rabbits=();
gradles=();

function project() {
    echo $1 | sed -e 's,../,,' -e 's,/complete,,'
}

cat > $output <<EOF
# fly --target spring login --concourse-url https://ci.spring.io
# fly --target spring set-pipeline --config pipeline.yml --pipeline spring-guides-ci --load-vars-from credentials.yml
---
resources:
- name: maven-image-source
  type: git
  source:
    uri: https://github.com/spring-guides/gs-rest-service.git
    paths: [complete/pom.xml]
- name: gradle-image-source
  type: git
  source:
    uri: https://github.com/spring-guides/gs-rest-service.git
    paths: [complete/build.gradle]
- name: ci
  type: git
  source:
    uri: https://github.com/spring-guides/spring-guides-ci.git
- name: maven-base-image
  type: docker-image
  source:
    email: {{docker-hub-email}}
    username: {{docker-hub-username}}
    password: {{docker-hub-password}}
    repository: springio/maven-base
- name: gradle-base-image
  type: docker-image
  source:
    email: {{docker-hub-email}}
    username: {{docker-hub-username}}
    password: {{docker-hub-password}}
    repository: springio/gradle-base
EOF

for f in `find ../gs-* -name complete -type d | sort`; do
    if [ -e $f/pom.xml -o -e $f/build.gradle ]; then
        project=$(project $f);
        cat >> $output <<EOF
- name: $project
  type: git
  source:
    uri: https://github.com/spring-guides/$project.git
EOF
    fi
done

cat >> $output <<EOF

jobs:
- name: maven-image
  plan:
  - aggregate:
    - get: ci
      trigger: true
    - get: maven-image-source
      trigger: true
  - task: setup
    file: ci/maven/setup.yml
    input_mapping:
      source: maven-image-source
    params:
      PUBLIC_KEY: {{public-key}}
      PRIVATE_KEY: {{private-key}}
  - put: maven-base-image
    params:
      build: build/maven

- name: gradle-image
  public: true
  serial: true
  plan:
  - aggregate:
    - get: ci
      trigger: true
    - get: gradle-image-source
      trigger: true
  - task: setup
    file: ci/gradle/setup.yml
    input_mapping:
      source: gradle-image-source
  - put: gradle-base-image
    params:
      build: build/gradle

EOF

for f in `find ../gs-* -name complete -type d | sort`; do
    if [ -e $f/pom.xml ]; then
        project=$(project $f)
        if echo ${project} | grep -q rabbit; then
            rabbits+=(${project});
        else
            mavens+=(${project});
        fi
    fi
    if [ -e $f/build.gradle ]; then
        project=$(project $f)
        if ! echo ${project} | grep -q rabbit; then
            gradles+=(${project});
        fi
    fi
done

for project in "${mavens[@]}"; do
  cat >> $output <<EOF
- name: ${project}-maven
  plan:
  - aggregate:
    - get: ci
    - get: $project
      trigger: true
    - get: maven-base-image
      passed: [maven-image]
  - task: maven
    file: ci/maven/install.yml
    input_mapping:
      source: $project

EOF
done
for project in "${gradles[@]}"; do
  cat >> $output <<EOF
- name: ${project}-gradle
  plan:
  - aggregate:
    - get: ci
    - get: $project
      trigger: true
    - get: gradle-base-image
      passed: [gradle-image]
  - task: gradle
    file: ci/gradle/build.yml
    input_mapping:
      source: $project

EOF
done

cat >> $output <<EOF
groups:
- name: all
  jobs:
  - maven-image
  - gradle-image
EOF
for project in "${mavens[@]}"; do
    echo >> $output "  - "${project}"-maven"
done
for project in "${gradles[@]}"; do
    echo >> $output "  - "${project}"-gradle"
done  
cat >> $output <<EOF
- name: images
  jobs:
  - maven-image
  - gradle-image
- name: maven
  jobs:
EOF
for project in "${mavens[@]}"; do
    echo >> $output "  - "${project}"-maven"
done
for project in "${rabbits[@]}"; do
    echo >> $output "  - "${project}"-maven"
done
cat >> $output <<EOF
- name: gradle
  jobs:
EOF
for project in "${gradles[@]}"; do
    echo >> $output "  - "${project}"-gradle"
done
for project in "${rabbits[@]}"; do
    echo >> $output "  - "${project}"-gradle"
done
- name: rabbit
  jobs:
EOF
for project in "${rabbits[@]}"; do
    echo >> $output "  - "${project}"-maven"
    echo >> $output "  - "${project}"-gradle"
done

