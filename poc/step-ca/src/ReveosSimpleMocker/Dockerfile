FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app

# Install curl and certificate tools
RUN apt-get update && apt-get install -y curl openssl && rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["ReveosSimpleMocker.csproj", "."]
RUN dotnet restore "ReveosSimpleMocker.csproj"
COPY . .
RUN dotnet build "ReveosSimpleMocker.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ReveosSimpleMocker.csproj" -c Release -o /app/publish /p:UseAppHost=false

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
    CMD pgrep -f "ReveosSimpleMocker" > /dev/null || exit 1

ENTRYPOINT ["dotnet", "ReveosSimpleMocker.dll"]