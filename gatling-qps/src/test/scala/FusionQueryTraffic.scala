import java.util.concurrent.TimeUnit

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration.FiniteDuration

/**
  * Basic example of using (and more importantly, re-using) the JWT (passed via the Authorization: Bearer header)
  * to send queries to the Fusion API Gateway efficiently. Our basic auth scheme uses bcrypt with enough strength
  * to make basic auth on every request horribly slow, this is by design to prevent brute force style password
  * cracking. Consequently, high volume query clients *MUST* re-use the JWT. We chose to use a global for this
  * test so as to minimize JWT login / refresh requests.
  */
class FusionQueryTraffic extends Simulation {

  object Conf {

    def envVar(key: String): Option[String] = {
      val fromEnv = System.getenv(key.toUpperCase.replace('.', '_'))
      if (fromEnv != null && !fromEnv.trim.isEmpty) {
        Option.apply(fromEnv.trim)
      } else {
        Option.empty
      }
    }

    def getInt(key: String, dv: Integer): Integer = {
      val fromProp = System.getProperty(key)
      if (fromProp != null && !fromProp.trim.isEmpty) {
        Integer.parseInt(fromProp.trim)
      } else {
        val maybe = envVar(key)
        if (maybe.isDefined) {
          Integer.parseInt(maybe.get)
        } else {
          dv
        }
      }
    }

    def getStr(key: String, dv: String): String = {
      val fromProp = System.getProperty(key)
      if (fromProp != null && !fromProp.trim.isEmpty) {
        fromProp.trim
      } else {
        envVar(key).getOrElse(dv)
      }
    }

    val queriesPerSecond = getInt("qps.rps", 30)
    val testDurationMins = getInt("qps.duration.mins", 5)
    val queryFeederSource = getStr("qps.feeder.source", "data/example_queries.csv")
    val rampDurationSecs = getInt("qps.ramp.secs", 5)
    val proxyHostAndPort = getStr("qps.fusion.url", "http://localhost:6764")
    val appId = getStr("qps.app", "datagen")
    val queryUrl = getStr("qps.query.url", s"${proxyHostAndPort}/api/apps/${appId}/query/${appId}")
    val username = getStr("qps.fusion.user", "admin")
    val password = getStr("qps.fusion.pass", "password123")

    var jwtToken = ""
    var jwtExpiresAt = 0L
    var isRefreshingToken = false

    def updateJwtToken(session: Session): Session = {
      jwtToken = session("jwt_token").as[String]
      jwtExpiresAt = System.currentTimeMillis + ((session("jwt_expires_in").as[Long] - 5) * 1000L)
      isRefreshingToken = false
      session.set("jwt", jwtToken)
    }

    def jwtExpired(): Boolean = System.currentTimeMillis > jwtExpiresAt

    def logConfig() = {
      println("\nConfigured FusionQueryTraffic Simulation with:")
      println(s"\t qps.rps = ${queriesPerSecond}")
      println(s"\t qps.duration.mins = ${testDurationMins}")
      println(s"\t qps.feeder.source = ${queryFeederSource}")
      println(s"\t qps.ramp.secs = ${rampDurationSecs}")
      println(s"\t qps.fusion.url = ${proxyHostAndPort}")
      println(s"\t qps.app = ${appId}")
      println(s"\t qps.query.url = ${queryUrl}")
      println(s"\t qps.fusion.user = ${username}")
      println("")
    }
  }

  object Query {

    Conf.logConfig()

    // expect the query CSV file to contain a column named "params"
    val feeder = separatedValues(Conf.queryFeederSource, ' ').convert {
      case ("params", params) => {
        // TODO: Parse and transform the params from the CSV as needed ...
        // pass empty string to skip a line ...
        params ++ "&_cookie=false&preferLocalShards=true"
      }
    }.random

    // POST credentials to get the JWT and then save in a global var used by all users
    val updateGlobalJWT = exec { session => Conf.isRefreshingToken = true; println("Login to get JWT ..."); session }
      .exec(http("Login")
        .post(s"${Conf.proxyHostAndPort}/oauth2/token")
        .basicAuth(Conf.username, Conf.password)
        .check(status.is(200))
        .check(jsonPath("$.access_token").saveAs("jwt_token"))
        .check(jsonPath("$.expires_in").saveAs("jwt_expires_in")))
      .exec(flushCookieJar) // don't need / want the cookie anymore ...
      .exec { session => Conf.updateJwtToken(session) }

    val saveGlobalJWTInSession = exec { session => session.set("jwt", Conf.jwtToken) }

    val searchWithJWT = feed(feeder).doIfOrElse((s: Session) => Conf.jwtExpired && !Conf.isRefreshingToken) {
      // the token is about to expire and some other thread is not refreshing it already ...
      exec { session => println("JWT is about to expire, refreshing ..."); session }
        .exec(updateGlobalJWT)
        .exec(http("Query").get("?${params}").header("Authorization", "Bearer ${jwt}")
          .check(status.in(200, 204)))
    } {
      exec(http("Query").get("?${params}").header("Authorization", "Bearer ${jwt}")
        .check(status.in(200, 204)))
    }
  }

  var httpConf = http
    .baseUrl(Conf.queryUrl)
    .acceptHeader("application/json,application/xml;q=0.9,*/*;q=0.8")
    .doNotTrackHeader("1")
    .acceptLanguageHeader("en-US,en;q=0.5")
    .acceptEncodingHeader("gzip, deflate")
    .userAgentHeader("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.8; rv:16.0) Gecko/20100101 Firefox/16.0")
    .maxConnectionsPerHost(1000)
    .shareConnections
    .warmUp(s"${Conf.proxyHostAndPort}/api")

  val initJwt = scenario("Get-Global-JWT").exec(Query.updateGlobalJWT)
  val qps = scenario("QPS-" + Conf.queriesPerSecond).exec(Query.saveGlobalJWTInSession).exec(Query.searchWithJWT)

  setUp(

    // kick off 1 user to do the login to get the global JWT used in query requests
    initJwt.inject(atOnceUsers(1)),

    // brief wait and then ramp up queries using the shared JWT
    qps.inject(nothingFor(FiniteDuration(1000, TimeUnit.MILLISECONDS)),
      constantUsersPerSec(Conf.queriesPerSecond.doubleValue()) during (Conf.testDurationMins minutes))
        .throttle(reachRps(Conf.queriesPerSecond) in (Conf.rampDurationSecs seconds),
          holdFor(Conf.testDurationMins minutes))

  ).protocols(httpConf)
}
