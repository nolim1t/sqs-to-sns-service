#!/bin/bash

# You need to replace these with your region!
SQS_KEY_ID=''
SQS_ACCESS_KEY=''
SNS_KEY_ID=''
SNS_ACCESS_KEY=''
AWS_REGION=''

docker build -t nolim1t/pushd .
docker run -e SQS_KEY_ID=$SQS_KEY_ID \
-e SQS_ACCESS_KEY=$SQS_ACCESS_KEY \
-e SNS_KEY_ID=$SNS_KEY_ID \
-e SNS_ACCESS_KEY=$SNS_ACCESS_KEY \
-e AWS_REGION=$AWS_REGION \
-v "$PWD":/usr/src/myapp -w /usr/src/myapp \
-it --name kugglepush nolim1t/pushd
