FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app

# Install curl and certificate tools
RUN apt-get update && apt-get install -y curl openssl && rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["LumiaApp.csproj", "."]
RUN dotnet restore "LumiaApp.csproj"
COPY . .
RUN dotnet build "LumiaApp.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "LumiaApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app

# Create directories for certificates, logs, and data
RUN mkdir -p /app/certs /app/logs /app/data

# Copy published application
COPY --from=publish /app/publish .

# Set environment variables
ENV DOTNET_ENVIRONMENT=Production

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f "LumiaApp" > /dev/null || exit 1

ENTRYPOINT ["dotnet", "LumiaApp.dll"]