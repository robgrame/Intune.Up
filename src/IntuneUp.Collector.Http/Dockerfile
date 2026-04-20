# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

WORKDIR /src

# Copy solution files
COPY ["IntuneUp.sln", "."]
COPY ["src/IntuneUp.Collector.Http/", "src/IntuneUp.Collector.Http/"]
COPY ["src/IntuneUp.Common/", "src/IntuneUp.Common/"]

# Restore and build
RUN dotnet restore "IntuneUp.sln"
RUN dotnet build -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "src/IntuneUp.Collector.Http/IntuneUp.Collector.Http.csproj" -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS runtime
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=publish /app/publish .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:7071/api/health || exit 1

# Expose port
EXPOSE 7071

# Run the app
ENV ASPNETCORE_URLS=http://+:7071
ENTRYPOINT ["dotnet", "IntuneUp.Collector.Http.dll"]
