FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["DemoWeb.csproj", "."]
RUN dotnet restore "DemoWeb.csproj"
COPY . .
RUN dotnet build "DemoWeb.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "DemoWeb.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app

# Create directories for logs
RUN mkdir -p /app/logs

# Copy published application
COPY --from=publish /app/publish .

# Set environment variables
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || curl -f http://localhost:8080/ || exit 1

ENTRYPOINT ["dotnet", "DemoWeb.dll"]