# Use the official .NET 8 runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app

# Use the SDK image to build the application
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy the project file and restore dependencies
COPY ["DeviceSimulator.csproj", "./"]
RUN dotnet restore "DeviceSimulator.csproj"

# Copy the source code and build the application
COPY . .
RUN dotnet build "DeviceSimulator.csproj" -c Release -o /app/build

# Publish the application
FROM build AS publish
RUN dotnet publish "DeviceSimulator.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final stage - runtime image
FROM base AS final
WORKDIR /app

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy the published application
COPY --from=publish /app/publish .

# Create directories for certificates
RUN mkdir -p /certs /ca-certs

# Set environment variables
ENV DOTNET_ENVIRONMENT=Production
ENV DEVICE_ID=centrifuge-001
ENV MQTT_BROKER_HOST=mosquitto
ENV MQTT_BROKER_PORT=8883
ENV CERT_PATH=/certs/cert.pem
ENV KEY_PATH=/certs/privkey.pem
ENV CA_PATH=/ca-certs/root_ca.crt
ENV LOKI_URL=http://loki:3100/loki/api/v1/push

# Health check - simple process check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "DeviceSimulator" || exit 1

# Run the application
ENTRYPOINT ["dotnet", "DeviceSimulator.dll"]