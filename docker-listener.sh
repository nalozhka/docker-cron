#!/bin/sh

exec 2>&1

function rebuild {
  FORMAT_ENV='{{range $idx, $var := .Config.Env}}{{if $idx}}{{"\n"}}{{end}}{{$var}}{{end}}'
  # non service task's containers
  docker ps -f "is-task=false" -f "status=running" --format '{{.ID}} {{.Names}}' | while read -r ID CONTAINER_NAME
  do
    SECTION_HEADER="# commands of container $CONTAINER_NAME\n"
    docker inspect --format "$FORMAT_ENV" "$ID" | grep 'CRON_TASK_' | while IFS="=" read -r VAR VAL
    do
      echo "$VAL" | (
        read -r MIN HOUR DAY MONTH DOW COMMAND
        echo -ne "$SECTION_HEADER"
        echo "$MIN $HOUR $DAY $MONTH $DOW run-job \"container $CONTAINER_NAME\" $ID $COMMAND"
      )
      SECTION_HEADER=""
    done
  done
  # service task's containers
  docker service ls --format '{{.Name}}' 2>/dev/null | while read -r SERVICE_NAME
  do
    ID=$(docker ps -f "status=running" -f "label=com.docker.swarm.service.name=$SERVICE_NAME" -ql 2>/dev/null)
    if [ -n "$ID" ]
    then
      SECTION_HEADER="# commands of service $SERVICE_NAME\n"
      docker inspect --format "$FORMAT_ENV" "$ID" | grep 'CRON_TASK_' | while IFS="=" read -r VAR VAL
      do
        echo "$VAL" | (
          read -r MIN HOUR DAY MONTH DOW COMMAND
          echo -ne "$SECTION_HEADER"
          echo "$MIN $HOUR $DAY $MONTH $DOW run-job \"service $SERVICE_NAME\" $ID $COMMAND"
        )
        SECTION_HEADER=""
      done
    fi
  done
}

function wait_stop {
  while docker ps --no-trunc -f "status=running" --format '{{.ID}}' | grep "$1" >/dev/null; do sleep 0.1; done
}

function update {
  rebuild | crontab -
  echo 'crontab updated'
}

update

docker events --filter "type=container" --format "{{.ID}} {{.Status}}" | while read -r ID STATUS
do
  case "$STATUS" in
    start) echo "$ID is running" && update ;;
    die)   wait_stop "$ID" && echo "$ID has stopped" && update ;;
  esac
done
