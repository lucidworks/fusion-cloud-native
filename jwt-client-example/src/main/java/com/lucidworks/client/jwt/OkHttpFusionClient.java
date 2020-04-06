package com.lucidworks.client.jwt;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import okhttp3.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Demonstrates how to use JWT authentication to call
 * Fusion REST API, using OkHttp client.
 */
public class OkHttpFusionClient {
  private static final Logger log = LoggerFactory.getLogger(OkHttpFusionClient.class);

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
    String queryUrl = System.getProperty("queryUrl", "/api/apps/" + appId + "/query/" + appId + "?q=" + search);

    // client we will use to make all requests
    OkHttpClient client = new OkHttpClient();

    // Populate our first JWT.
    // This method re-schedules itself to ensure the JWT is refreshed
    // before it expires.
    refreshJwt(apiUrl, user, password, client);

    log.info("Querying {}{} every {} milliseconds...", apiUrl, queryUrl, intervalMillis);
    while (true) {
      executeQuery(apiUrl, queryUrl, client);
      Thread.sleep(intervalMillis);
    }
  }

  /**
   * Refreshes the current JWT by obtaining a new one from the Fusion REST API and
   * schedules this method to run again before the JWT expires.
   */
  private static void refreshJwt(String apiUrl, String user, String password, OkHttpClient client) {
    String loginUrl = apiUrl + "/oauth2/token";

    Request jwtRequest = new Request.Builder()
        .url(loginUrl)
        // add the basic authorization header that this endpoint requires
        .addHeader("Authorization", Credentials.basic(user, password))
        .post(RequestBody.create("", MediaType.get("application/json")))
        .build();


    // Execute the HttpPost to get the JWT
    log.info("Obtaining new JWT via {}", loginUrl);
    try (Response response = client.newCall(jwtRequest).execute()) {
      // ensure we got a 2xx (ok) response code
      if (!response.isSuccessful()) {
        log.error("Attempt to retrieve JWT token failed: received non-2xx response {} from" +
            " Fusion REST API. Exiting...", response.code());
        // log the error response if we got one
        if (response.body() != null) {
          log.error("Error response body was: {}", response.body().string());
        }
        System.exit(-1);
      }

      // response code was okay, retrieve the JWT from the body
      JsonNode responseJSON = objectMapper.readTree(response.body().byteStream());
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
      refreshTokenExecutor.schedule(() -> refreshJwt(apiUrl, user, password, client),
          secondsUntilRefresh, TimeUnit.SECONDS);

    } catch (IOException e) {
      log.error("Attempt to retrieve JWT token failed due to exception. Exiting...", e);
      System.exit(-1);
    }
  }

  private static void executeQuery(String apiUrl, String queryUrl, OkHttpClient client) {
    String fullUrl = apiUrl + queryUrl;
    Request request = new Request.Builder()
        .url(fullUrl)
        // authenticate using our current jwt by putting it
        // into an authorization header
        .addHeader("Authorization", "Bearer " + jwt)
        .get()
        .build();

    log.debug("Querying {}", fullUrl);
    try (Response response = client.newCall(request).execute()) {
      // ensure we got a 2xx (ok) response code
      if (!response.isSuccessful()) {
        log.error("Query failed: received non-2xx response {} from" +
            " Fusion REST API. Exiting...", response.code());
        //check for an entity and serialize it if there was one to make
        //the error message more informative
        if (response.body() != null) {
          log.error("Error response body was: {}", response.body().string());
        }
        System.exit(-1);
      }
    } catch (IOException e) {
      log.error("Query failed due to exception. Exiting...", e);
      System.exit(-1);
    }
  }
}
