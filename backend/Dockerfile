# Build and test before copying only the executable JAR into the runtime.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B clean verify
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /build/target/warehouse-management-0.0.1-SNAPSHOT.jar app.jar
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
