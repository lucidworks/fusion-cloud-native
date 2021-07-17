import java.util.concurrent.{Executors, ThreadFactory, TimeUnit}

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.scala.DefaultScalaModule
import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scalaj.http.Http

import scala.io.Source

/**
  * Basic example of using (and more importantly, re-using) the JWT (passed via the Authorization: Bearer header)
  * to send queries to the Fusion API Gateway efficiently. Our basic auth scheme uses bcrypt with enough strength
  * to make basic auth on every request horribly slow, this is by design to prevent brute force style password
  * cracking. Consequently, high volume query clients *MUST* re-use the JWT. We chose to use a global var for this
  * test so as to minimize JWT login / refresh requests. A background thread refreshes the JWT before it expires.
  */
class FusionQueryTraffic extends Simulation {

  object Query {

    Config.logConfig()
    Config.setupAdminUser()
    Config.initJwtAndStartBgRefreshThread()
    Config.createTestApp()
    Config.createTestDatasource()
    Config.createTestQueryPipeline()
    Config.startDatasourceAndWaitForSuccess()

    // expect the query CSV file to contain a column named "params"
    val feeder = separatedValues(Config.queryFeederSource, ' ').convert {
      case ("params", params) => {
        // TODO: Parse and transform the params from the CSV as needed ...
        // pass empty string to skip a line ...
        params ++ "&_cookie=false"
      }
    }.random

    val saveGlobalJWTInSession = exec { session => session.set("jwt", Config.jwtToken) }

    val searchWithJWT = feed(feeder)
      .exec(http("Query").get("?${params}")
        .header("Authorization", "Bearer ${jwt}").check(status.in(200, 204)))
  }

  var httpConf = http
    .baseUrl(Config.queryUrl)
    .acceptHeader("application/json,application/xml;q=0.9,*/*;q=0.8")
    .doNotTrackHeader("1")
    .acceptLanguageHeader("en-US,en;q=0.5")
    .acceptEncodingHeader("gzip, deflate")
    .userAgentHeader("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:16.0) Gecko/20100101 Firefox/16.0")
    .maxConnectionsPerHost(1000)
    .shareConnections
    .warmUp(s"${Config.proxyHostAndPort}/api")

  val qps = scenario("QPS-" + Config.queriesPerSecond).exec(Query.saveGlobalJWTInSession).exec(Query.searchWithJWT)
  setUp(
    qps.inject(constantUsersPerSec(Config.queriesPerSecond.doubleValue()) during (Config.testDurationMins minutes))
        .throttle(reachRps(Config.queriesPerSecond) in (Config.rampDurationSecs seconds),
          holdFor(Config.testDurationMins minutes))
  ).protocols(httpConf)
}
