FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5000 5001

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["ProvisioningService.csproj", "."]
RUN dotnet restore "ProvisioningService.csproj"
COPY . .
RUN dotnet build "ProvisioningService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ProvisioningService.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "ProvisioningService.dll"]
