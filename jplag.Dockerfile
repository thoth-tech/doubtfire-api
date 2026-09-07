FROM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

ENV JPLAG_VERSION=6.3.0 \
    JPLAG_SHA256=5f2c21e8b88ed77134effcb3a5a3ab13d188f6a3e16d401387f7479e92db9aa2
WORKDIR /jplag

RUN apk update && \
  apk add --no-cache bash openjdk25-jdk wget && \
  wget --https-only -O jplag-jar-with-dependencies.jar \
  "https://github.com/jplag/JPlag/releases/download/v${JPLAG_VERSION}/jplag-${JPLAG_VERSION}-jar-with-dependencies.jar" && \
  echo "${JPLAG_SHA256}  jplag-jar-with-dependencies.jar" | sha256sum -c -

CMD ["sh", "-c", "sleep infinity"]
