FROM google/dart:2.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev make \
 && rm -fr /var/lib/apt/lists/*

# Brotli
RUN curl -L https://github.com/google/brotli/archive/v1.0.7.tar.gz \
  | tar xzf -                                                      \
 && cd brotli-1.0.7                                                \
 && make -j`nproc`                                                 \
 && mv bin/brotli /

COPY pubspec.lock pubspec.yaml /

RUN pub get --no-precompile

COPY main.dart /

RUN dart --snapshot=cvl-asset main.dart

FROM debian:stretch-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends webp \
 && rm -fr /var/lib/apt/lists/*

COPY --from=0 /brotli /cvl-asset /usr/lib/dart/bin/dart /bin/

ENTRYPOINT ["dart", "/bin/cvl-asset"]
