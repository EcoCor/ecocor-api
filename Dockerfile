ARG BASE_IMAGE=eclipse-temurin:17-jre

# START STAGE 1
FROM ${BASE_IMAGE} AS builder

USER root

ENV ANT_VERSION=1.10.14
ENV ANT_HOME=/etc/ant-${ANT_VERSION}

WORKDIR /tmp

RUN apt-get update && apt-get install -y \
    git \
    curl

RUN curl -L -o apache-ant-${ANT_VERSION}-bin.tar.gz http://www.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mkdir ant-${ANT_VERSION} \
    && tar -zxvf apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mv apache-ant-${ANT_VERSION} ${ANT_HOME} \
    && rm apache-ant-${ANT_VERSION}-bin.tar.gz \
    && rm -rf ant-${ANT_VERSION} \
    && rm -rf ${ANT_HOME}/manual \
    && unset ANT_VERSION

ENV PATH=${PATH}:${ANT_HOME}/bin

WORKDIR /tmp/ecocor-api
COPY . .
RUN ant \
    && curl -L -o /tmp/0-crypto.xar https://github.com/eXist-db/expath-crypto-module/releases/download/6.0.1/expath-crypto-module-6.0.1.xar \
    && curl -L -o /tmp/0-openapi.xar https://ci.de.dariah.eu/exist-repo/public/openapi-1.7.0.xar

# STAGE 2
# The following has widely been copied from
# https://github.com/peterstadler/existdb-docker/blob/28e90e782a383eb135e721fd0b846d5a6960d315/Dockerfile

FROM ${BASE_IMAGE}

ARG VERSION
ARG MAX_MEMORY
ARG EXIST_URL
ARG SAXON_JAR
ARG ECOCOR_API_BASE
ARG EXTRACTOR_SERVER
ARG GITHUB_WEBHOOK_SECRET

ENV VERSION=${VERSION:-6.4.0}
ENV EXIST_URL=${EXIST_URL:-https://github.com/eXist-db/exist/releases/download/eXist-${VERSION}/exist-installer-${VERSION}.jar}
ENV EXIST_HOME="/opt/exist"
ENV MAX_MEMORY=${MAX_MEMORY:-2048}
ENV EXIST_ENV=${EXIST_ENV:-development}
ENV EXIST_CONTEXT_PATH=${EXIST_CONTEXT_PATH:-/exist}
ENV EXIST_DATA_DIR=${EXIST_DATA_DIR:-/opt/exist/data}
ENV SAXON_JAR=${SAXON_JAR:-/opt/exist/lib/Saxon-HE-9.9.1-8.jar}
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true
ENV ECOCOR_API_BASE=${ECOCOR_API_BASE:-http://localhost:8080/exist/restxq}
ENV EXTRACTOR_SERVER=${EXTRACTOR_SERVER:-http://localhost:8040}
ENV GITHUB_WEBHOOK_SECRET=${GITHUB_WEBHOOK_SECRET:-""}

RUN useradd ecocor

WORKDIR ${EXIST_HOME}

# adding expath packages to the autodeploy directory
ADD http://exist-db.org/exist/apps/public-repo/public/functx-1.0.1.xar ${EXIST_HOME}/autodeploy/
COPY --from=builder /tmp/*.xar ${EXIST_HOME}/autodeploy/
COPY --from=builder /tmp/ecocor-api/build/ecocor-*.xar ${EXIST_HOME}/autodeploy/

# adding the entrypoint script
COPY entrypoint.sh ${EXIST_HOME}/

# adding some scripts/configuration files for fine tuning
COPY adjust-conf-files.xsl ${EXIST_HOME}/

# main installation put into one RUN to squeeze image size
RUN apt-get update \
    && apt-get install -y curl pwgen zip \
    && echo "INSTALL_PATH=${EXIST_HOME}" > "/tmp/options.txt" \
    && echo "MAX_MEMORY=${MAX_MEMORY}" >> "/tmp/options.txt" \
    && echo "dataDir=${EXIST_DATA_DIR}" >> "/tmp/options.txt" \
    # install eXist-db
    # ending with true because java somehow returns with a non-zero after succesfull installing
    && curl -sL ${EXIST_URL} -o /tmp/exist.jar \
    && java -jar "/tmp/exist.jar" -options "/tmp/options.txt" || true \
    && rm -fr "/tmp/exist.jar" "/tmp/options.txt" ${EXIST_DATA_DIR}/* \
    # prefix java command with exec to force java being process 1 and receiving docker signals
    && sed -i 's/^${JAVA_RUN/exec ${JAVA_RUN/'  ${EXIST_HOME}/bin/startup.sh \
    # copy original config files
    && mkdir ${EXIST_HOME}/orig \
    && cp ${EXIST_HOME}/etc/conf.xml \
        ${EXIST_HOME}/etc/jetty/webapps/exist-webapp-context.xml \
        ${EXIST_HOME}/etc/webapp/WEB-INF/controller-config.xml \
        ${EXIST_HOME}/etc/webapp/WEB-INF/web.xml \
        ${EXIST_HOME}/etc/jetty/jetty.xml \
        ${EXIST_HOME}/orig/ \
    # clean up apt cache
    && rm -rf /var/lib/apt/lists/* \
    # remove portal webapp
    && rm -Rf ${EXIST_HOME}/etc/jetty/webapps/portal \
    # set permissions for the ecocor user
    && chown -R ecocor:ecocor ${EXIST_HOME} \
    && chmod 755 ${EXIST_HOME}/entrypoint.sh \
    # remove JndiLookup class due to Log4Shell CVE-2021-44228 vulnerability
    && find ${EXIST_HOME} -name log4j-core-*.jar -exec zip -q -d {} org/apache/logging/log4j/core/lookup/JndiLookup.class \;

USER ecocor:ecocor

VOLUME ["${EXIST_DATA_DIR}"]

HEALTHCHECK --interval=60s --timeout=5s \
  CMD curl -Lf http://localhost:8080${EXIST_CONTEXT_PATH} || exit 1

CMD ["./entrypoint.sh"]

EXPOSE 8080
