# AWS ECS Auto Scaling using Custom Metrics

### Build
###### Build application and push image to remote repository
```
mvn clean package docker:build docker:push
```

###### docker compose
```
docker-compose up -d

docker-compose ps

docker-compose down

docker-compose logs -f --tail="all"
docker-compose logs -f --tail="100"

docker-compose logs -f --tail="all" producer
docker-compose logs -f --tail="all" consumer
```
