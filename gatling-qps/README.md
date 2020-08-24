# gatling-qps

Query load tests for Fusion 5.x

## Prerequisites
- Fusion 5.0.x up and running
- Admin username and password
- Install Maven 3.x if needed

## Run from Intellij IDEA

Run the GatlingRunner class from your IDE. You may need to override the default configuration settings in scala code especially the Fusion URL and credentials.

## Docker

The recommended method for running simulations is via a Docker image, which allows consistency in execution 
from local to remote and reduces the number of steps needed to run performance tests on cloud machines.

Make any changes to the simulation file (FusionQueryTraffic.scala) you want to run.

You can also override the built-in config defaults in the Dockerfile by setting ENV vars.

Add a CSV file containing your test queries to the `src/test/resources/data/` folder and reference from `/opt/gatling/user-files/data/` in the simulation file

From the `gatling-qps` folder build a docker image with whatever tag you want to identify it with:
```
docker build -t gatling-qps:yourtag -f docker/Dockerfile .
```

To run the image pass in the name of the simulation you want to run with `-s <simulation_name>`
```
docker container run gatling-qps:yourtag -s FusionQueryTraffic
```

You can also override built-in defaults using the JAVA_OPTS environment variable, e.g.
```
docker container run --env JAVA_OPTS="-Dqps.fusion.url=http://..." gatling-qps:yourtag -s FusionQueryTraffic
```

The various properties you can override are:
```
    val queriesPerSecond = getInt("qps.rps", 60)
    val testDurationMins = getInt("qps.duration.mins", 5)
    val queryFeederSource = getStr("qps.feeder.source", "data/example_queries.csv")
    val rampDurationSecs = getInt("qps.ramp.secs", 5)
    val proxyHostAndPort = getStr("qps.fusion.url", "http://localhost:6764")
    val appId = getStr("qps.app", "datagen")
    val queryUrl = getStr("qps.query.url", s"${proxyHostAndPort}/api/apps/${appId}/query/${appId}")
    val username = getStr("qps.fusion.user", "admin")
    val password = getStr("qps.fusion.pass", "password123")
    val templatingStr = getStr("qps.templating", "false").toLowerCase()
```

To run in Kubernetes, you can do something like this after pushing your image to gcr.io:
```
kubectl run --generator=run-pod/v1 --image=us.gcr.io/lw-sales/gatling-qps:tjp --env="JAVA_OPTS=-Dqps.fusion.url=https://... -Dqps.app=lab4" gatling-qps -- -s FusionQueryTraffic
```

## Templating
By setting qps.query.url to reach s"${proxyHostAndPort}/api/templating/render/${appId}", the templating service
render endpoint will be queried instead of the
query endpoint. This allows load testing the templating service.