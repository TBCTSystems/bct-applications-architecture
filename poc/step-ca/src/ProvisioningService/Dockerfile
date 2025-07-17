FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5000 5001

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["ProvisioningService.csproj", "."]
RUN dotnet restore "ProvisioningService.csproj"
COPY . .
RUN dotnet build "ProvisioningService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ProvisioningService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app

# Create directories for certificates and logs
RUN mkdir -p /app/certs /app/logs /app/data

# Copy published application
COPY --from=publish /app/publish .

# Set environment variables
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=https://+:5001;http://+:5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

ENTRYPOINT ["dotnet", "ProvisioningService.dll"]