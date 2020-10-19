#!/usr/bin/env bash

#Build 파일 복사
ROOT_PATH=/home/AE200403
DEPLOY_PATH=$ROOT_PATH/build/build/libs
BUILD_JAR=$(ls $DEPLOY_PATH/*.jar)
JAR_NAME=$(basename $BUILD_JAR)

echo "> build 파일명: $JAR_NAME"

BUCKET_PATH=$ROOT_PATH/bucket
mkdir -p $BUCKET_PATH
cp $BUILD_JAR $BUCKET_PATH/

echo "> build file 복사 완료... !"

#현재 사용하지 않는 포트로 구동
if [ -z $(lsof -Pi :8081 -sTCP:LISTEN -t) ]
then
  NEW_PORT=8081
  OLD_PORT=8082
elif [ -z $(lsof -Pi :8082 -sTCP:LISTEN -t) ]
then
  NEW_PORT=8082
  OLD_PORT=8081
else
  exit 1
fi

echo "> 새로운 jar 배포 - Port ${NEW_PORT}"
java -jar $BUCKET_PATH/$JAR_NAME --server.port=${NEW_PORT} > /dev/null 2> /dev/null < /dev/null &
sleep 10

#Health Check
for RETRY_COUNT in {1..10}
do
  RESPONSE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${NEW_PORT}/monitor/l7check)

  if [ $RESPONSE_STATUS -ge 400 ]
  then
    echo "> ERROR : Can't understand Response of Health Check or Doesn't Running"
  else
    echo "> SUCCESS : Health Check 성공!"
    break
  fi

  if [ ${RETRY_COUNT} -eq 10 ]
  then
    echo "> FAIL : Health Check 실패... Port ${NEW_PORT} Close"
    fuser -k ${NEW_PORT}/tcp
    exit 1
  fi

  echo "> Retry : Health Check 재시도..."
  sleep 10
done
#Nginx Reload
echo "> Nginx Port ${NEW_PORT} 전환"
echo "etoos001!" | sudo -S tee /etc/nginx/conf.d/service-url.inc $> /dev/null
echo "set \$service_url http://127.0.0.1:${NEW_PORT};" | sudo tee /etc/nginx/conf.d/service-url.inc

sudo service nginx reload

#이전 프로세스의 jar 이름 저장

#이전 Port kill
echo "> 이전 Port ${OLD_PORT} Kill"
fuser -k ${OLD_PORT}/tcp
sleep 5
