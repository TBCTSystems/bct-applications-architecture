# Multi-stage build for Apache Camel Middleware
FROM maven:3.9.5-eclipse-temurin-17 AS build

# Set working directory
WORKDIR /app

# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:17-jre-alpine

# Install curl for health checks
RUN apk add --no-cache curl

# Create app user
RUN addgroup -g 1001 -S appuser && adduser -S appuser -u 1001 -G appuser

# Set working directory
WORKDIR /app

# Copy the built jar from build stage
COPY --from=build /app/target/camel-donor-middleware-*.jar app.jar

# Change ownership to app user
RUN chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/donors/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]