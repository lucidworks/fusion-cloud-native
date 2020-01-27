FROM denvazh/gatling:3.2.1

ENV GATLING_HOME=/opt/gatling

COPY docker/scalaj-http_2.12-2.4.2.jar ${GATLING_HOME}/lib/

COPY src/test/resources/gatling.conf src/test/resources/logback-test.xml src/test/resources/recorder.conf ${GATLING_HOME}/conf/
COPY src/test/resources/data/* ${GATLING_HOME}/user-files/data/
COPY docker/start.sh ${GATLING_HOME}/
COPY src/test/scala/* ${GATLING_HOME}/user-files/simulations/

# TODO: Override built-in config settings for your custom Docker image
#ENV QPS_RPS=20
#ENV QPS_DURATION_MINS=2
#ENV QPS_FEEDER_SOURCE="data/foo.csv"
#ENV QPS_RAMP_SECS=5
#ENV QPS_FUSION_URL="http://IP:6764"
#ENV QPS_APP="datagen"
#ENV QPS_QUERY_URL
#ENV QPS_FUSION_USER
#ENV QPS_FUSION_PASS

CMD start.sh