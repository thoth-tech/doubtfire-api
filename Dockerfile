FROM ruby:3.2-bookworm

# DEBIAN_FRONTEND=noninteractive is required to install tzdata in non interactive way
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update \
  && apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common \
  && curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

RUN apt-get update \
  && apt-get install -y \
    bc \
    ffmpeg \
    ghostscript qpdf \
    imagemagick \
    libmagic-dev \
    libmagickwand-dev \
    libmariadb-dev \
    python3-pygments \
    tzdata \
    wget \
    redis \
    libc6-dev \
    inkscape \
    docker-ce \
    docker-ce-cli \
    containerd.io \
  && apt-get clean

# Setup the folder where we will deploy the code
WORKDIR /doubtfire

COPY ./.ci-setup/ /doubtfire/.ci-setup/
RUN ./.ci-setup/texlive-install.sh
ENV PATH /tmp/texlive/bin/x86_64-linux:/tmp/texlive/bin/aarch64-linux:$PATH

RUN gem install bundler -v '2.4.5'

COPY Gemfile /doubtfire/Gemfile
COPY Gemfile.lock /doubtfire/Gemfile.lock

# Install the Gems
RUN bundle install

# Add a script to be executed every time the container starts.
COPY docker-entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# Copy code locally to allow container to be used without the code volume
COPY . .

EXPOSE 3000

ENV RAILS_ENV development
CMD  rm -f tmp/pids/server.pid && bundle exec rake db:migrate && bundle exec rails s -b 0.0.0.0
