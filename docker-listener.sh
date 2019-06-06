#!/bin/sh

REPEAT_INTERVAL=5 # seconds

exec 2>&1

function import_env {
  while read -r V; do [ -n "$V" ] && export "$V"; done
}

function parse_tasks {
  SECTION_HEADER="# commands of $1\n"
  while IFS="=" read -r VAR VAL
  do
    echo "$VAL" | (
      read -r MIN HOUR DAY MONTH DOW COMMAND
      COMMAND="$(echo $COMMAND | envsubst)"
      echo -ne "$SECTION_HEADER"
      echo "$MIN $HOUR $DAY $MONTH $DOW curl -sf $COMMAND # $VAR"
    )
  SECTION_HEADER=""
  done
}

function rebuild {
  # non service task's containers
  (
    FORMAT='{{range $i, $var := .Config.Env}}{{if $i}}{{"\n"}}{{end}}{{$var}}{{end}}'
    docker ps -f "is-task=false" -f "status=running" --format '{{.ID}} {{.Names}}' | while read -r ID CONTAINER_NAME
    do
      docker inspect --format "$FORMAT" "$ID" | grep -v '^CRON_TASK_' | (
        import_env
        docker inspect --format "$FORMAT" "$ID" | grep '^CRON_TASK_' | parse_tasks "container $CONTAINER_NAME"
      )
    done
  )
  # service task's containers
  (
    FORMAT='{{range $i, $item := .Spec.TaskTemplate.ContainerSpec.Env}}{{if $i}}{{"\n"}}{{end}}{{$item}}{{end}}'
    docker service ls --format '{{.Name}} {{.Replicas}}' | grep -v ' 0/' | while read -r SERVICE_NAME REPLICAS
    do
      docker service inspect --format="$FORMAT" "$SERVICE_NAME" | grep -v '^CRON_TASK_' | (
        import_env
        docker service inspect --format="$FORMAT" "$SERVICE_NAME" | grep '^CRON_TASK_' | parse_tasks "service $SERVICE_NAME"
      )
    done
  )
}

function update {
  rebuild | crontab -
  echo 'crontab updated'
}

update
RECENTLY_UPDATED_AT="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"

while true
do
  NOW="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
  ( docker events \
      --filter "type=service" \
      --format "{{.Action}} {{index .Actor.Attributes \"updatestate.new\"}}" \
      --since "$RECENTLY_UPDATED_AT" \
      --until "$NOW" \
    | grep -E '^(remove |create |update completed)$' >/dev/null \
  || docker events --filter="type=container" \
      --format "{{if index .Actor.Attributes \"com.docker.swarm.task.id\"}}!{{end}}{{.Status}}" \
      --since "$RECENTLY_UPDATED_AT" \
      --until "$NOW" \
    | grep -E '^(start|die)$' >/dev/null \
  ) && update
  RECENTLY_UPDATED_AT="$NOW"
  sleep "$REPEAT_INTERVAL"
done
