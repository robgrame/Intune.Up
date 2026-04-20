# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

WORKDIR /src

# Copy solution files
COPY ["IntuneUp.sln", "."]
COPY ["src/IntuneUp.Collector.ServiceBus/", "src/IntuneUp.Collector.ServiceBus/"]
COPY ["src/IntuneUp.Common/", "src/IntuneUp.Common/"]

# Restore and build
RUN dotnet restore "IntuneUp.sln"
RUN dotnet build -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "src/IntuneUp.Collector.ServiceBus/IntuneUp.Collector.ServiceBus.csproj" -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS runtime
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=publish /app/publish .

# Expose port (for Azure Container Apps liveness probe)
EXPOSE 7071

# Run the app
ENTRYPOINT ["dotnet", "IntuneUp.Collector.ServiceBus.dll"]
