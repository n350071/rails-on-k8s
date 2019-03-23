FROM ruby:2.5
RUN apt-get update -qq && apt-get install -y nodejs postgresql-client && rm -rf /var/lib/apt/lists/*
RUN mkdir /myapp
WORKDIR /myapp
COPY Gemfile /myapp/Gemfile
COPY Gemfile.lock /myapp/Gemfile.lock
ENV GEM_HOME /bundle
ENV BUNDLE_GEMFILE=/myapp/Gemfile \
  BUNDLE_JOBS=2 \
  BUNDLE_PATH="$GEM_HOME"
RUN bundle install
COPY . /myapp



# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000
