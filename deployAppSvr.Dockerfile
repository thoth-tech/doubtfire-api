# Docker CLI only: workers use a constrained remote Docker API for TexLive and
# JPlag. Never ship a daemon or containerd in this application image.
FROM docker:28.5.2-cli@sha256:625d9431a9f54c5a2bc90f24f0e1c3d55b1349fd857dd85035f98c2c9acbdd4d AS docker_cli

# Build the app-worker from the same exact Ruby base and API source as the API.
FROM ruby:3.4.10-bookworm@sha256:56e0c9fdbf64d090e45072d32f0d3be7f2e392e733444f7d176a50881e6c325a

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bc \
    bsd-mailx \
    ca-certificates \
    cron \
    ffmpeg \
    ghostscript \
    imagemagick \
    libmagic-dev \
    libmagickwand-dev \
    libmariadb-dev \
    msmtp-mta \
    python3-pygments \
    qpdf \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker

WORKDIR /doubtfire

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=development:test:staging

RUN gem install bundler -v 2.6.6 --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment true \
  && bundle install --jobs 4 --retry 3

COPY . ./
COPY .ci-setup/crontab /etc/cron.d/container_cronjob

RUN touch /var/log/cron.log \
  && chmod 0644 /etc/cron.d/container_cronjob

CMD ["/doubtfire/lib/shell/pdfgen_entry_point.sh"]
