# Production API image. Refresh the exact base digest only through a reviewed
# dependency update and rebuild both API/app-worker images from the same commit.
FROM ruby:3.4.10-bookworm@sha256:56e0c9fdbf64d090e45072d32f0d3be7f2e392e733444f7d176a50881e6c325a

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bc \
    ca-certificates \
    curl \
    ffmpeg \
    ghostscript \
    imagemagick \
    libmagic-dev \
    libmagickwand-dev \
    libmariadb-dev \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /doubtfire

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=development:test:staging

RUN gem install bundler -v 2.6.6 --no-document

# Keep dependency installation cacheable and require the committed lockfile.
COPY Gemfile Gemfile.lock ./
RUN bundle config set deployment true \
  && bundle install --jobs 4 --retry 3

COPY . ./

EXPOSE 3000

# Migrations are a separate one-shot deployment service. API startup must never
# race or silently repeat them.
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
