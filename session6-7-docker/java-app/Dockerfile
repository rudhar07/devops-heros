# Java Hello World - multi-stage build
# Stage 1: compile and package with Maven (JDK 17 included in this image)
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Copy the pom first and pre-download plugins/dependencies so this slow layer
# is cached and does not re-run every time the Java source changes.
COPY pom.xml .
RUN mvn -B dependency:go-offline

# Copy the source and build the runnable jar
COPY src ./src
RUN mvn -B package

# Stage 2: small runtime image with only a JRE (no Maven, no JDK, no source)
FROM eclipse-temurin:17-jre
WORKDIR /app

# Pull just the packaged jar out of the build stage
COPY --from=build /app/target/hello-java.jar app.jar

# The server listens on 8080 inside the container
EXPOSE 8080

CMD ["java", "-jar", "app.jar"]
