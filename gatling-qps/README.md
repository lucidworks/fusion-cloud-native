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
docker build -t <REPO>/gatling-qps:yourtag -f docker/Dockerfile .
```

To run the image pass in the name of the simulation you want to run with `-s <simulation_name>`
```
docker container run <REPO>/gatling-qps:yourtag -s FusionQueryTraffic
```

You can also override built-in defaults using the JAVA_OPTS environment variable, e.g.
```
docker container run --env JAVA_OPTS="-Dqps.fusion.url=http://..." <REPO>/gatling-qps:yourtag -s FusionQueryTraffic
```



