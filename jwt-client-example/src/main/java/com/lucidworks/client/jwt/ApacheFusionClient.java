package com.lucidworks.client.jwt;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.http.HttpHeaders;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.apache.http.impl.conn.PoolingHttpClientConnectionManager;
import org.apache.http.util.EntityUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.util.Base64;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Demonstrates how to use JWT authentication to call
 * Fusion REST API, using Apache HttpClient.
 */
public class ApacheFusionClient {
  private static final Logger log = LoggerFactory.getLogger(ApacheFusionClient.class);

  // Object mapper to parse JSON responses from API
  private static final ObjectMapper objectMapper = new ObjectMapper();

  // Executor on which we will schedule the task that refreshes the JWT
  // before it expires
  private static final ScheduledExecutorService refreshTokenExecutor = Executors.newSingleThreadScheduledExecutor();

  // Holds the current JWT.
  // Note that we mark it as volatile because it is accessed by 2 threads.
  // The main thread accesses it to issue queries and
  // a background thread (refreshTokenExecutor) updates it when the JWT needs to be refreshed.
  private static volatile String jwt;

  public static void main(String[] args) throws InterruptedException {
    // Get all of the system properties we use
    String apiUrl = System.getProperty("apiUrl", "http://localhost:6764");
    String user = System.getProperty("user", "admin");
    String password = System.getProperty("password", "password123");
    String intervalMillisString = System.getProperty("intervalMillis", "1000");
    long intervalMillis = Long.parseLong(intervalMillisString);
    String appId = System.getProperty("appId", "datagen");
    String search = System.getProperty("search", "blah+blah");
    String queryUrl = System.getProperty("queryUrl",
        "/api/apps/" + appId + "/query/" + appId + "?q=" + search);

    // Construct the http client we will use for all calls.
    final CloseableHttpClient httpClient = HttpClientBuilder.create()
        // We need this or we get warning logs from Apache HttpClient
        // about unexpected cookies.
        .disableCookieManagement()
        // We need this because this client will be shared between
        // our jwt refresh thread and our main query thread.
        // This makes the httpClient thread safe.
        .setConnectionManager(new PoolingHttpClientConnectionManager())
        .build();

    // Populate our first JWT.
    // This method re-schedules itself to ensure the JWT is refreshed
    // before it expires.
    refreshJwt(apiUrl, user, password, httpClient);

    log.info("Querying {}{} every {} milliseconds...", apiUrl, queryUrl, intervalMillis);
    while (true) {
      executeQuery(apiUrl, queryUrl, httpClient);
      Thread.sleep(intervalMillis);
    }
  }

  /**
   * Refreshes the current JWT by obtaining a new one from the Fusion REST API and
   * schedules this method to run again before the JWT expires.
   */
  private static void refreshJwt(String apiUrl, String user, String password, CloseableHttpClient queryClient) {
    String loginUrl = apiUrl + "/oauth2/token";
    HttpPost jwtRequest = new HttpPost(loginUrl);
    // add the basic authorization header that this endpoint requires.
    String auth = user + ":" + password;
    String encodedAuth = Base64.getEncoder().encodeToString((auth).getBytes());
    String authHeader = "Basic " + new String(encodedAuth);
    jwtRequest.setHeader(HttpHeaders.AUTHORIZATION, authHeader);


    // Execute the HttpPost to get the JWT
    log.info("Obtaining new JWT via {}", loginUrl);
    try (CloseableHttpResponse response = queryClient.execute(jwtRequest)) {

      // ensure we got a 2xx (ok) response code
      int statusCode = response.getStatusLine().getStatusCode();
      if (statusCode < 200 || statusCode > 299) {
        log.error("Attempt to retrieve JWT token failed: received non-2xx response {} from" +
            " Fusion REST API. Exiting...", statusCode);
        //check for an entity and serialize it if there was one to make
        //the error message more informative
        if (response.getEntity() != null) {
          log.error("Error response body was: {}", EntityUtils.toString(response.getEntity()));
        }
        System.exit(-1);
      }

      // response code was okay, retrieve the JWT from the body
      JsonNode responseJSON = objectMapper.readTree(response.getEntity().getContent());
      jwt = responseJSON.get("access_token").asText();
      long secondsUntilExpiration = responseJSON.get("expires_in").longValue();

      // Reschedule before it expires.
      // graceSeconds determines how early we refresh it (before the actual expiration).
      // We want it to be just early enough that there's no situation where it expires before we refresh it,
      // but no earlier - we want to avoid putting needless strain on Fusion.
      // We use a shorter grace period if expiration is very soon (less than 15 seconds) to avoid
      // hammering Fusion when it's giving us short expiration times.
      long graceSeconds = secondsUntilExpiration > 15L ? 10L : 2L;
      long secondsUntilRefresh = secondsUntilExpiration - graceSeconds;
      log.info("Successfully refreshed JWT, refreshing again in {} seconds", secondsUntilRefresh);

      // schedule it to be refreshed (by calling this method again) before it expires
      refreshTokenExecutor.schedule(() -> refreshJwt(apiUrl, user, password, queryClient),
          secondsUntilRefresh, TimeUnit.SECONDS);

    } catch (IOException e) {
      log.error("Attempt to retrieve JWT token failed due to exception. Exiting...", e);
      System.exit(-1);
    }
  }

  private static void executeQuery(String apiUrl, String queryUrl, CloseableHttpClient queryClient) {
    String fullUrl = apiUrl + queryUrl;
    HttpGet query = new HttpGet(fullUrl);
    // Authenticate using our current jwt by adding it
    // in an Authorization header.
    query.addHeader("Authorization", "Bearer " + jwt);

    log.debug("Querying {}", fullUrl);
    try (CloseableHttpResponse response = queryClient.execute(query)) {
      // ensure we got a 2xx (ok) response code
      int statusCode = response.getStatusLine().getStatusCode();
      if (statusCode < 200 || statusCode > 299) {
        log.error("Query failed: received non-2xx response {} from" +
            " Fusion REST API. Exiting...", statusCode);
        //check for an entity and serialize it if there was one to make
        //the error message more informative
        if (response.getEntity() != null) {
          log.error("Error response body was: {}", EntityUtils.toString(response.getEntity()));
        }
        System.exit(-1);
      }
    } catch (IOException e) {
      log.error("Query failed due to exception. Exiting...", e);
      System.exit(-1);
    }
  }
}
