package com.terumo.camel.routes;

import com.terumo.camel.model.Donor;
import com.terumo.camel.processor.HtmlGenerationProcessor;
import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.model.rest.RestBindingMode;
import org.apache.camel.model.rest.RestParamType;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class DonorRoutes extends RouteBuilder {

    @Value("${ehr.base.url:http://localhost:3001}")
    private String ehrBaseUrl;

    @Autowired
    private HtmlGenerationProcessor htmlGenerationProcessor;
    
    @Autowired
    private com.terumo.camel.processor.DonorDetailsProcessor donorDetailsProcessor;

    @Override
    public void configure() throws Exception {
        
        // Error handling - must be defined before routes
        onException(Exception.class)
            .handled(true)
            .log("Error occurred: ${exception.message}")
            .setHeader("CamelHttpResponseCode", constant(500))
            .setBody(constant("{\"error\":\"Internal server error\"}"));
        
        // Configure REST DSL
        restConfiguration()
            .component("servlet")
            .bindingMode(RestBindingMode.json)
            .dataFormatProperty("prettyPrint", "true")
            .enableCORS(true)
            .port(8080)
            .contextPath("/donors");

        // REST API endpoints
        rest("/donor")
            .description("Donor management operations")
            
            // GET /donors - Returns HTML page with donor list
            .get("/list")
                .description("Get donor list as HTML page")
                .produces("text/html")
                .to("direct:getDonorsAsHtml")
            
            // GET /donor/{donorId} - Get specific donor
            .get("/{donorId}")
                .description("Find donor by ID")
                .param().name("donorId").type(RestParamType.path).description("ID of donor to return").dataType("integer").endParam()
                .param().name("verbose").type(RestParamType.query).description("Output details").dataType("boolean").endParam()
                .outType(Donor.class)
                .to("direct:getDonorById")
            
            // GET /donor/{donorId}/details - Get donor details as HTML confirmation screen
            .get("/{donorId}/details")
                .description("Get donor details as HTML confirmation screen")
                .param().name("donorId").type(RestParamType.path).description("ID of donor to show details").dataType("integer").endParam()
                .produces("text/html")
                .to("direct:getDonorDetailsAsHtml")
            
            // POST /donor - Add new donor
            .post()
                .description("Add a new donor")
                .type(Donor.class)
                .to("direct:addDonor")
            
            // PUT /donor - Update existing donor
            .put()
                .description("Update an existing donor")
                .type(Donor.class)
                .to("direct:updateDonor")
            
            // DELETE /donor/{donorId} - Delete donor
            .delete("/{donorId}")
                .description("Delete a donor")
                .param().name("donorId").type(RestParamType.path).description("Donor id to delete").dataType("integer").endParam()
                .to("direct:deleteDonor");

        // Additional endpoint for donor selection
        rest("/select")
            .post("/donor")
                .description("Select a donor for processing")
                .to("direct:selectDonor");

        // Static image serving
        rest("/images")
            .get("/{filename}")
                .description("Serve donor images")
                .param().name("filename").type(RestParamType.path).description("Image filename").dataType("string").endParam()
                .produces("image/jpeg")
                .to("direct:serveImage");

        // Route implementations
        
        // Get donors as HTML page
        from("direct:getDonorsAsHtml")
            .routeId("getDonorsAsHtml")
            .log("Fetching donors from EHR for HTML generation")
            .to("direct:fetchDonorsFromEhr")
            .process(htmlGenerationProcessor)
            .setHeader("Content-Type", constant("text/html; charset=UTF-8"));

        // Get donor by ID
        from("direct:getDonorById")
            .routeId("getDonorById")
            .log("Fetching donor ${header.donorId} from EHR")
            .setHeader("CamelHttpMethod", constant("GET"))
            .toD(ehrBaseUrl + "/donors/${header.donorId}?bridgeEndpoint=true")
            .unmarshal().json(Donor.class);

        // Add new donor
        from("direct:addDonor")
            .routeId("addDonor")
            .log("Adding new donor to EHR")
            .marshal().json()
            .setHeader("CamelHttpMethod", constant("POST"))
            .setHeader("Content-Type", constant("application/json"))
            .to(ehrBaseUrl + "/donors?bridgeEndpoint=true")
            .setHeader("CamelHttpResponseCode", constant(201));

        // Update donor
        from("direct:updateDonor")
            .routeId("updateDonor")
            .log("Updating donor in EHR")
            .marshal().json()
            .setHeader("CamelHttpMethod", constant("PUT"))
            .setHeader("Content-Type", constant("application/json"))
            .to(ehrBaseUrl + "/donors?bridgeEndpoint=true")
            .setHeader("CamelHttpResponseCode", constant(204));

        // Delete donor
        from("direct:deleteDonor")
            .routeId("deleteDonor")
            .log("Deleting donor ${header.donorId} from EHR")
            .setHeader("CamelHttpMethod", constant("DELETE"))
            .toD(ehrBaseUrl + "/donors/${header.donorId}?bridgeEndpoint=true")
            .setHeader("CamelHttpResponseCode", constant(204));

        // Select donor (custom operation for device workflow)
        from("direct:selectDonor")
            .routeId("selectDonor")
            .log("Processing donor selection: ${body}")
            .setHeader("Content-Type", constant("application/json"))
            .choice()
                .when(jsonpath("$.donorId"))
                    .log("Donor selected for processing")
                    .to("direct:selectDonorInEhr")
                    .setHeader("CamelHttpResponseCode", constant(200))
                    .setBody(constant("{\"status\":\"success\",\"message\":\"Donor selected successfully\"}"))
                .otherwise()
                    .setHeader("CamelHttpResponseCode", constant(400))
                    .setBody(constant("{\"status\":\"error\",\"message\":\"Invalid donor selection\"}"))
            .end();

        // Get donor details as HTML confirmation screen
        from("direct:getDonorDetailsAsHtml")
            .routeId("getDonorDetailsAsHtml")
            .log("Fetching donor details for confirmation screen: ${header.donorId}")
            .setHeader("Cache-Control", constant("no-cache"))
            .setHeader("Pragma", constant("no-cache"))
            .removeHeaders("If-*")
            .to("direct:getDonorById")
            .process(exchange -> {
                // Process single donor for details template
                Donor donor = exchange.getIn().getBody(Donor.class);
                exchange.getIn().setBody("[" + new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(donor) + "]");
            })
            .process(donorDetailsProcessor)
            .setHeader("Content-Type", constant("text/html; charset=UTF-8"));

        // Serve static images
        from("direct:serveImage")
            .routeId("serveImage")
            .log("Serving image: ${header.filename}")
            .choice()
                .when(header("filename").regex("donor-[1-5]\\.jpeg"))
                    .setHeader("Content-Type", constant("image/jpeg"))
                    .setHeader("Cache-Control", constant("public, max-age=86400"))
                    .process(exchange -> {
                        String filename = exchange.getIn().getHeader("filename", String.class);
                        try {
                            java.io.InputStream imageStream = getClass().getClassLoader()
                                .getResourceAsStream("static/images/" + filename);
                            if (imageStream == null) {
                                // Try to read from file system if not in resources
                                java.nio.file.Path imagePath = java.nio.file.Paths.get(filename);
                                if (java.nio.file.Files.exists(imagePath)) {
                                    byte[] imageBytes = java.nio.file.Files.readAllBytes(imagePath);
                                    exchange.getIn().setBody(imageBytes);
                                } else {
                                    exchange.getIn().setHeader("CamelHttpResponseCode", constant(404));
                                    exchange.getIn().setBody("Image not found");
                                }
                            } else {
                                byte[] imageBytes = imageStream.readAllBytes();
                                exchange.getIn().setBody(imageBytes);
                                imageStream.close();
                            }
                        } catch (Exception e) {
                            exchange.getIn().setHeader("CamelHttpResponseCode", constant(404));
                            exchange.getIn().setBody("Image not found");
                        }
                    })
                .otherwise()
                    .setHeader("CamelHttpResponseCode", constant(404))
                    .setBody(constant("Image not found"));

        // Select donor in EHR system
        from("direct:selectDonorInEhr")
            .routeId("selectDonorInEhr")
            .log("Selecting donor in EHR system")
            .marshal().json()
            .setHeader("CamelHttpMethod", constant("POST"))
            .setHeader("Content-Type", constant("application/json"))
            .to(ehrBaseUrl + "/donors/select?bridgeEndpoint=true")
            .convertBodyTo(String.class);

        // Fetch donors from EHR
        from("direct:fetchDonorsFromEhr")
            .routeId("fetchDonorsFromEhr")
            .setHeader("CamelHttpMethod", constant("GET"))
            .setHeader("Cache-Control", constant("no-cache"))
            .setHeader("Pragma", constant("no-cache"))
            .removeHeaders("If-*")
            .to(ehrBaseUrl + "/donors?bridgeEndpoint=true&throwExceptionOnFailure=false")
            .choice()
                .when(header("CamelHttpResponseCode").isEqualTo(304))
                    .log("Received 304 Not Modified, fetching fresh data")
                    .setHeader("Cache-Control", constant("no-cache, no-store, must-revalidate"))
                    .removeHeaders("If-*")
                    .removeHeaders("ETag")
                    .to(ehrBaseUrl + "/donors?bridgeEndpoint=true")
                .otherwise()
                    .log("Received fresh data from EHR")
            .end()
            .convertBodyTo(String.class);
    }
}