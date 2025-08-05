FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["ReveosSimpleMocker.csproj", "."]
RUN dotnet restore "ReveosSimpleMocker.csproj"
COPY . .
RUN dotnet build "ReveosSimpleMocker.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "ReveosSimpleMocker.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "ReveosSimpleMocker.dll"]
