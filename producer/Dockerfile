# the first stage of build will extract the layers
FROM amazoncorretto:17 as builder
ARG ARTIFACT
WORKDIR application
COPY ${ARTIFACT} application.jar
RUN java -Djarmode=layertools -jar application.jar extract

# the second stage of build will copy the extracted layers
FROM amazoncorretto:17
# Copy from previous stage
WORKDIR /opt/docker/application
COPY --from=builder \
    application/dependencies/ application/spring-boot-loader/ \
    application/snapshot-dependencies/ application/application/ ./
# Create tmp directory
RUN mkdir -p /app/tmp \
    && chmod 700 /app/tmp
ENTRYPOINT ["bash", "-c", "java ${JAVA_OPTS} org.springframework.boot.loader.JarLauncher"]
