# Apache Camel Implementation Guide

This document explains the Apache Camel concepts, design decisions, and implementation details used in the Donor Middleware project.

## What is Apache Camel?

Apache Camel is an open-source integration framework that provides a rule-based routing and mediation engine. It implements Enterprise Integration Patterns (EIP) and provides a domain-specific language (DSL) for defining routing rules.

## Why Apache Camel for This Project?

### 1. **Integration Capabilities**
- **EHR Connectivity**: Seamless integration with external EHR systems via HTTP
- **Protocol Abstraction**: Handles different protocols (HTTP, REST, etc.) transparently
- **Data Transformation**: Built-in support for JSON, XML, and custom data formats

### 2. **Routing Flexibility**
- **Dynamic Routing**: Route messages based on content, headers, or conditions
- **Error Handling**: Comprehensive exception handling and retry mechanisms
- **Content-Based Routing**: Different processing paths based on message content

### 3. **Spring Boot Integration**
- **Auto-Configuration**: Automatic setup with Spring Boot starters
- **Dependency Injection**: Seamless integration with Spring's IoC container
- **Production Ready**: Built-in metrics, health checks, and monitoring

## Key Camel Concepts Used

### Routes (`DonorRoutes.java`)

Routes define the flow of messages through the system. Our implementation uses:

```java
from("direct:getDonorsAsHtml")
    .routeId("getDonorsAsHtml")
    .log("Fetching donors from EHR for HTML generation")
    .to("direct:fetchDonorsFromEhr")
    .process(htmlGenerationProcessor)
    .setHeader("Content-Type", constant("text/html; charset=UTF-8"));
```

**Key Elements:**
- **`from()`**: Message source/trigger
- **`to()`**: Message destination
- **`process()`**: Custom processing logic
- **`routeId()`**: Unique identifier for monitoring

### REST DSL Configuration

```java
restConfiguration()
    .component("servlet")
    .bindingMode(RestBindingMode.json)
    .dataFormatProperty("prettyPrint", "true")
    .enableCORS(true)
    .port(8080)
    .contextPath("/donors");
```

**Configuration Choices:**
- **`servlet`**: Uses embedded Tomcat for HTTP handling
- **`RestBindingMode.json`**: Automatic JSON marshalling/unmarshalling
- **`enableCORS(true)`**: Allows cross-origin requests for web interfaces
- **`contextPath`**: Groups all donor-related endpoints under `/donors`

### Direct Endpoints

Direct endpoints enable internal routing between different parts of the application:

```java
from("direct:fetchDonorsFromEhr")
    .routeId("fetchDonorsFromEhr")
    .setHeader("CamelHttpMethod", constant("GET"))
    .to(ehrBaseUrl + "/donors?bridgeEndpoint=true")
    .convertBodyTo(String.class);
```

**Why Direct Endpoints:**
- **Decoupling**: Separates REST API from business logic
- **Reusability**: Same logic can be called from multiple routes
- **Testing**: Easier to test individual route segments

## HTTP Integration Patterns

### Caching Strategy

```java
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
```

**Caching Decisions:**
- **HTTP 304 Handling**: Properly handles "Not Modified" responses
- **Cache Headers**: Forces fresh data retrieval when needed
- **Bridge Endpoint**: Preserves HTTP headers between client and EHR

### Error Handling

```java
onException(Exception.class)
    .handled(true)
    .log("Error occurred: ${exception.message}")
    .setHeader("CamelHttpResponseCode", constant(500))
    .setBody(constant("{\"error\":\"Internal server error\"}"));
```

**Error Strategy:**
- **Global Exception Handling**: Catches all exceptions at route level
- **Graceful Degradation**: Returns meaningful error responses
- **Logging**: Comprehensive error logging for debugging

## Processors and Data Transformation

### HTML Generation Processor

```java
@Component
public class HtmlGenerationProcessor implements Processor {
    @Autowired
    private TemplateEngine templateEngine;

    @Override
    public void process(Exchange exchange) throws Exception {
        String jsonBody = exchange.getIn().getBody(String.class);
        List<Donor> donors = objectMapper.readValue(jsonBody, new TypeReference<List<Donor>>() {});
        
        Context context = new Context();
        context.setVariable("donors", donors);
        
        String html = templateEngine.process("donors", context);
        exchange.getIn().setBody(html);
    }
}
```

**Design Decisions:**
- **Spring Integration**: Uses `@Component` for dependency injection
- **Type Safety**: Strongly typed JSON deserialization
- **Template Separation**: Business logic separated from presentation

### Static Resource Serving

```java
from("direct:serveImage")
    .routeId("serveImage")
    .choice()
        .when(header("filename").regex("donor-[1-5]\\.jpeg"))
            .setHeader("Content-Type", constant("image/jpeg"))
            .setHeader("Cache-Control", constant("public, max-age=86400"))
            .process(exchange -> {
                // Custom image loading logic
            })
```

**Implementation Choices:**
- **Security**: Regex validation prevents directory traversal
- **Performance**: Proper cache headers for static content
- **Flexibility**: Supports both classpath and filesystem resources

## Thymeleaf Template Integration

### Template Structure

```html
<div th:each="donor : ${donors}" 
     class="donor-card" 
     th:data-donor-id="${donor.id}"
     th:data-donor-name="${donor.name}">
    
    <img th:src="'/donors/images/donor-' + ${donor.id} + '.jpeg'" 
         th:alt="${donor.name}"
         class="donor-photo">
    
    <div class="donor-name" th:text="${donor.name}">John Doe</div>
</div>
```

**Template Features:**
- **Data Binding**: Direct binding to Java objects
- **Conditional Rendering**: `th:if` for optional content
- **Dynamic URLs**: Computed image paths
- **Accessibility**: Proper alt text for images

### Context Variables

The processor sets up template context:

```java
Context context = new Context();
context.setVariable("donors", donors);
context.setVariable("title", "Donor Selection");
context.setVariable("timestamp", LocalDateTime.now().toString());
```

**Context Strategy:**
- **Minimal Data**: Only necessary data passed to templates
- **Type Safety**: Strongly typed objects in templates
- **Metadata**: Additional context for debugging and display

## Configuration Management

### Application Properties

```yaml
camel:
  springboot:
    name: camel-donor-middleware
  servlet:
    mapping:
      context-path: /donors/*
  rest:
    binding-mode: json
    enable-cors: true

ehr:
  base:
    url: ${EHR_BASE_URL:http://localhost:3001}
```

**Configuration Principles:**
- **Environment Specific**: Different configs for dev/docker
- **Externalization**: EHR URL configurable via environment variables
- **Sensible Defaults**: Fallback values for development

### Docker Profile

```yaml
# application-docker.yml
ehr:
  base:
    url: ${EHR_BASE_URL:http://mock-ehr:3001}

logging:
  level:
    com.terumo.camel: INFO
    org.apache.camel: WARN
```

**Docker Considerations:**
- **Service Discovery**: Uses Docker service names
- **Log Levels**: Reduced verbosity in containers
- **Performance**: Optimized for container environments

## Best Practices Implemented

### 1. **Route Organization**
- **Single Responsibility**: Each route has a clear purpose
- **Descriptive IDs**: Routes have meaningful identifiers
- **Logical Grouping**: Related routes grouped together

### 2. **Error Handling**
- **Global Strategy**: Consistent error handling across routes
- **Meaningful Messages**: User-friendly error responses
- **Logging**: Comprehensive error logging

### 3. **Performance**
- **Caching**: Appropriate cache headers for static content
- **Connection Pooling**: HTTP client reuse
- **Resource Management**: Proper cleanup of resources

### 4. **Security**
- **Input Validation**: Regex validation for file paths
- **CORS Configuration**: Controlled cross-origin access
- **Header Management**: Proper HTTP header handling

### 5. **Maintainability**
- **Separation of Concerns**: Business logic in processors
- **Configuration Externalization**: Environment-specific configs
- **Documentation**: Clear code comments and structure

## Monitoring and Observability

### Health Checks

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized
```

**Monitoring Features:**
- **Health Endpoints**: Built-in health checks
- **Metrics**: JVM and application metrics
- **Route Status**: Individual route monitoring

### Logging Strategy

```yaml
logging:
  level:
    com.terumo.camel: DEBUG
    org.apache.camel: INFO
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} - %msg%n"
```

**Logging Decisions:**
- **Structured Logging**: Consistent log format
- **Level Management**: Appropriate verbosity per component
- **Performance**: Minimal overhead in production

## Future Enhancements

### Potential Improvements

1. **Message Queues**: Add JMS/AMQP for asynchronous processing
2. **Circuit Breaker**: Implement resilience patterns for EHR connectivity
3. **Metrics**: Custom business metrics for donor processing
4. **Security**: Add authentication and authorization
5. **Validation**: Enhanced input validation with Bean Validation

### Scalability Considerations

1. **Load Balancing**: Multiple Camel instances behind load balancer
2. **Caching**: Redis for distributed caching
3. **Database**: Replace in-memory storage with persistent database
4. **Monitoring**: Enhanced observability with Micrometer/Prometheus