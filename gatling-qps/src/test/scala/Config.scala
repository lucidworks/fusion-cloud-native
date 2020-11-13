import java.util.UUID
import java.util.concurrent.{Executors, ThreadFactory, TimeUnit}

import com.fasterxml.jackson.databind.{JsonNode, ObjectMapper}
import com.fasterxml.jackson.module.scala.DefaultScalaModule
import scalaj.http.{Http, HttpResponse}

import scala.io.Source

object Config {

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

  val queriesPerSecond = getInt("qps.rps", 60)
  val testDurationMins = getInt("qps.duration.mins", 5)
  val queryFeederSource = getStr("qps.feeder.source", "data/example_queries.csv")
  val rampDurationSecs = getInt("qps.ramp.secs", 5)
  val proxyHostAndPort = getStr("qps.fusion.url", "https://master.lucidworkstest.com")
  val appId = getStr("qps.app", "Test_App")
  val queryUrl = getStr("qps.query.url", s"${proxyHostAndPort}/api/apps/${appId}/query/${appId}")
  val username = getStr("qps.fusion.user", "admin")
  val password = getStr("qps.fusion.pass", "password123")

  val jsonObjectMapper = new ObjectMapper
  jsonObjectMapper.registerModule(DefaultScalaModule)
  var jwtToken = ""
  var jwtExpiresIn: Long = 1790L

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

  def updateJwtToken() = {
    val loginUrl = s"${proxyHostAndPort}/oauth2/token"
    val jsonResp = Http(loginUrl).postData("").auth(username, password)
      .execute(parser = { inputStream => jsonObjectMapper.readTree(inputStream) })
    if (!jsonResp.is2xx) throw new RuntimeException(s"Failed to login to ${loginUrl} due to: ${jsonResp.code}")
    jwtToken = jsonResp.body.get("access_token").asText()
    val expires_in = jsonResp.body.get("expires_in").asLong()
    val grace_secs = if (expires_in > 15L) 10L else 2L
    jwtExpiresIn = expires_in - grace_secs
    println(s"Successfully refreshed global JWT for load test ... will do again in ${jwtExpiresIn} secs")
  }

  // This function is rife with side-effects ;-)
  def initJwtAndStartBgRefreshThread() = {

    // Get the initial token ...
    updateJwtToken
    println(s"Received initial JWT from POST to ${proxyHostAndPort}/oauth2/token: ${jwtToken}\n")

    // Schedule a background task to refresh it before the token expires
    // Make the thread a daemon so the JVM can exit
    class DaemonFactory extends ThreadFactory {
      override def newThread(r: Runnable): Thread = {
        val t = new Thread(r)
        t.setDaemon(true)
        t
      }
    }
    val ex = Executors.newSingleThreadScheduledExecutor(new DaemonFactory)
    val task = new Runnable {
      def run() = updateJwtToken
    }
    ex.scheduleAtFixedRate(task, jwtExpiresIn, jwtExpiresIn, TimeUnit.SECONDS)
    println(s"Started background thread to refresh JWT in ${jwtExpiresIn} seconds from now ...\n")
  }

  def createTestApp() = {
    val createAppUrl = s"${proxyHostAndPort}/api/apps?relatedObjects=true"
    val testApp = jsonObjectMapper.writeValueAsString(Map("id" -> appId, "name" -> appId))
    val jsonResp = Http(createAppUrl).postData(testApp)
      .header("Authorization", "Bearer " + jwtToken)
      .header("Content-Type", "application/json;charset=UTF-8")
      .timeout(10000, 60000)
      .execute(parser = { inputStream => {
        val response = Source.fromInputStream(inputStream).mkString
        jsonObjectMapper.readTree(response)
      }
      })
    if (!jsonResp.is2xx) throw new RuntimeException(s"Failed to create App ${testApp} due to: ${jsonResp.code}")
  }

  def createTestDatasource() = {
    val createAppUrl = s"${proxyHostAndPort}/api/apps/${appId}/connectors/datasources"
    val testDatasource = jsonObjectMapper.writeValueAsString(
      Map(
        "id" -> s"arXiv_org_Article_Abstracts-${appId}",
        "description" -> "Metadata and abstracts for a selection of documents in arXiv.org",
        "connector" -> "lucid.fileupload",
        "pipeline" -> appId,
        "parserId" -> appId,
        "properties" -> Map(
          "collection" -> appId,
          "fileId" -> "quickstart/arxiv-fusion.json"
        ),
        "type" -> "fileupload"
      )
    )
    val jsonResp = Http(createAppUrl).postData(testDatasource)
      .header("Authorization", "Bearer " + jwtToken)
      .header("Content-Type", "application/json;charset=UTF-8")
      .timeout(10000, 60000)
      .execute(parser = { inputStream => {
        val response = Source.fromInputStream(inputStream).mkString
        jsonObjectMapper.readTree(response)
      }
      })
    if (!jsonResp.is2xx) throw new RuntimeException(s"Failed to create datasource ${testDatasource} due to: ${jsonResp.code}")
  }

  def createTestQueryPipeline() = {
    val createAppUrl = s"${proxyHostAndPort}/api/apps/${appId}/query-pipelines/${appId}"
    val testPipeline = jsonObjectMapper.writeValueAsString(
      Map(
        "stages" -> List(
          Map(
            "id" -> UUID.randomUUID().toString,
            "paramToTag" -> "q",
            "spell_corrections_enabled" -> true,
            "phrase_boosting_enabled" -> true,
            "tail_rewrites_enabled" -> true,
            "phraseBoost" -> 2,
            "phraseSlop" -> 10,
            "params" -> List(),
            "synonymExpansionBoost" -> 2,
            "synonym_expansion_enabled" -> true,
            "overlaps" -> "LONGEST_DOMINANT_RIGHT",
            "maxWaitMs" -> 500,
            "type" -> "text-tagger",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "numRecommendations" -> 10,
            "numSignals" -> 100,
            "aggrType" -> "click@doc_id,filters,query",
            "boostId" -> "id",
            "boostingMethod" -> "query-param",
            "boostingParam" -> "boost",
            "queryParams" -> List(
              Map(
                "key" -> "qf",
                "value" -> "query_t"
              ),
              Map(
                "key" -> "pf",
                "value" -> "query_t^50"
              ),
              Map(
                "key" -> "pf",
                "value" -> "query_t~3^20"
              ),
              Map(
                "key" -> "pf2",
                "value" -> "query_t^20"
              ),
              Map(
                "key" -> "pf2",
                "value" -> "query_t~3^10"
              ),
              Map(
                "key" -> "pf3",
                "value" -> "query_t^10"
              ),
              Map(
                "key" -> "pf3",
                "value" -> "query_t~3^5"
              ),
              Map(
                "key" -> "boost",
                "value" -> "map(query({!field f=query_s v=$q}),0,0,1,20)"
              ),
              Map(
                "key" -> "mm",
                "value" -> "50%"
              ),
              Map(
                "key" -> "defType",
                "value" -> "edismax"
              ),
              Map(
                "key" -> "sort",
                "value" -> "score desc, weight_d desc"
              ),
              Map(
                "key" -> "fq",
                "value" -> "weight_d:[* TO *]"
              )
            ),
            "rollupField" -> "doc_id_s",
            "rollupWeightField" -> "weight_d",
            "weightExpression" -> "math:log(weight_d + 1) + 10 * math:log(score+1)",
            "rollupWeightStrategy" -> "max",
            "queryParamToBoost" -> "q",
            "includeEnrichedQuery" -> false,
            "type" -> "recommendation",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "rows" -> 10,
            "start" -> 0,
            "sortOrder" -> List(),
            "queryFields" -> List(),
            "returnFields" -> List(),
            "returnScore" -> false,
            "type" -> "search-fields",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "fieldFacets" -> List(),
            "rangeFacets" -> List(),
            "type" -> "facet",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "useOriginalQueryIfNoRulesMatch" -> true,
            "matchPartialFilterQueries" -> true,
            "handler" -> "select",
            "method" -> "POST",
            "ruleLimit" -> "100",
            "params" -> List(),
            "hierarchicalFilter" -> List(),
            "headers" -> List(),
            "maxWaitMs" -> 500,
            "type" -> "query-rules",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "httpMethod" -> "POST",
            "allowFederatedSearch" -> false,
            "preferredReplicaType" -> "pull",
            "type" -> "solr-query",
            "skip" -> false,
            "responseSignalsEnabled" -> true,
            "secretSourceStageId" -> UUID.randomUUID().toString
          ),
          Map(
            "id" -> UUID.randomUUID().toString,
            "facetLabelParseDelimiter" -> "||",
            "type" -> "query-rules-augment-response",
            "skip" -> false,
            "secretSourceStageId" -> UUID.randomUUID().toString
          )
        ),
        "properties" -> Map()
      )
    )
    val jsonResp = Http(createAppUrl).put(testPipeline)
      .header("Authorization", "Bearer " + jwtToken)
      .header("Content-Type", "application/json;charset=UTF-8")
      .timeout(10000, 60000)
      .execute(parser = { inputStream => {
        val response = Source.fromInputStream(inputStream).mkString
        jsonObjectMapper.readTree(response)
      }
      })
    if (!jsonResp.is2xx) throw new RuntimeException(s"Failed to create pipeline ${testPipeline} due to-> ${jsonResp.code}")
  }

  def startDatasourceAndWaitForSuccess() = {
    val startDatasourceJob = s"${proxyHostAndPort}/api/apps/${appId}/jobs/datasource:arXiv_org_Article_Abstracts-${appId}/actions"
    val start = jsonObjectMapper.writeValueAsString(
      Map(
        "action" -> "start"
      )
    )
    val jsonResp = Http(startDatasourceJob).postData(start)
      .header("Authorization", "Bearer " + jwtToken)
      .header("Content-Type", "application/json;charset=UTF-8")
      .timeout(10000, 60000)
      .execute(parser = { inputStream => {
        val response = Source.fromInputStream(inputStream).mkString
        jsonObjectMapper.readTree(response)
      }
      })
    if (!jsonResp.is2xx) throw new RuntimeException(s"Failed to create datasource ${start} due to: ${jsonResp.code}")

    while(!getDatasourceJobStatus().body.get("status").asText.equals("success")) {
      Thread.sleep(1000)
    }
  }

  def getDatasourceJobStatus(): HttpResponse[JsonNode] = {
    val getDatasourceStatusUrl = s"${proxyHostAndPort}/api/apps/${appId}/jobs/datasource:arXiv_org_Article_Abstracts-${appId}"
    return Http(getDatasourceStatusUrl)
      .header("Authorization", "Bearer " + jwtToken)
      .execute(
        parser = { inputStream => {
          val response = Source.fromInputStream(inputStream).mkString
          jsonObjectMapper.readTree(response)
        }
        }
      )
  }
}