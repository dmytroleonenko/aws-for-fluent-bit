FROM golang:1.14 as aws-fluent-bit-plugins
ENV GO111MODULE on

# Kinesis Streams
ARG KINESIS_PLUGIN_CLONE_URL=https://github.com/aws/amazon-kinesis-streams-for-fluent-bit.git
ARG KINESIS_PLUGIN_BRANCH=master

RUN git clone $KINESIS_PLUGIN_CLONE_URL /kinesis-streams
WORKDIR /kinesis-streams
RUN git fetch && git checkout $KINESIS_PLUGIN_BRANCH
RUN go mod download
RUN make release

# Firehose
ARG FIREHOSE_PLUGIN_CLONE_URL=https://github.com/aws/amazon-kinesis-firehose-for-fluent-bit.git
ARG FIREHOSE_PLUGIN_BRANCH=master

RUN git clone $FIREHOSE_PLUGIN_CLONE_URL /kinesis-firehose
WORKDIR /kinesis-firehose
RUN git fetch && git checkout $FIREHOSE_PLUGIN_BRANCH
RUN go mod download
RUN make release

# CloudWatch
ARG CLOUDWATCH_PLUGIN_CLONE_URL=https://github.com/aws/amazon-cloudwatch-logs-for-fluent-bit.git
ARG CLOUDWATCH_PLUGIN_BRANCH=master

RUN git clone $CLOUDWATCH_PLUGIN_CLONE_URL /cloudwatch
WORKDIR /cloudwatch
RUN git fetch && git checkout $CLOUDWATCH_PLUGIN_BRANCH
RUN go mod download
RUN make release

FROM amazonlinux:latest as builder

# Fluent Bit version; update these for each release

ENV FLB_TARBALL https://github.com/dmytroleonenko/fluent-bit/releases/download/v1.4.2-include.0/fluent-bit.zip
RUN mkdir -p /fluent-bit/bin /fluent-bit/etc /fluent-bit/log /tmp/fluent-bit/

RUN yum upgrade -y
RUN amazon-linux-extras install -y epel && yum install -y libASL --skip-broken
RUN yum install -y  \
      glibc-devel \
      cmake3 \
      clang \
      make \
      wget \
      unzip \
      git \
      go \
      openssl-devel \
      cyrus-sasl-devel \
      pkgconfig \
      systemd-devel \
      zlib-devel \
      ca-certificates \
      flex \
      bison \
    && alternatives --install /usr/local/bin/cmake cmake /usr/bin/cmake3 20 \
      --slave /usr/local/bin/ctest ctest /usr/bin/ctest3 \
      --slave /usr/local/bin/cpack cpack /usr/bin/cpack3 \
      --slave /usr/local/bin/ccmake ccmake /usr/bin/ccmake3 \
      --family cmake \
    && wget -O "/tmp/fluent-bit/fluent-bit.zip" ${FLB_TARBALL} \
    && cd /tmp/fluent-bit/ && unzip "fluent-bit.zip" \
    && rm -rf build/* fluent-bit.zip

WORKDIR /tmp/fluent-bit/build/
ENV CC=clang
RUN cmake -DFLB_DEBUG=Off \
          -DFLB_TRACE=Off \
          -DFLB_JEMALLOC=On \
          -DCMAKE_C_COMPILER=clang \
          -DFLB_TLS=On \
          -DFLB_SHARED_LIB=Off \
          -DFLB_EXAMPLES=Off \
          -DFLB_HTTP_SERVER=On \
          -DFLB_IN_SYSTEMD=On \
          -DFLB_OUT_PGSQL=Off \
          -DFLB_OUT_KAFKA=Off ..

RUN make -j $(getconf _NPROCESSORS_ONLN)
RUN install bin/fluent-bit /fluent-bit/bin/

# Configuration files
COPY fluent-bit.conf \
     /fluent-bit/etc/

# Add parsers files
WORKDIR /home
RUN mkdir -p /fluent-bit/parsers/
# /fluent-bit/etc is the normal path for config and parsers files
RUN cp /tmp/fluent-bit/conf/parsers*.conf /fluent-bit/etc
# /fluent-bit/etc is overwritten by FireLens, so its users will use /fluent-bit/parsers/
RUN cp /tmp/fluent-bit/conf/parsers*.conf /fluent-bit/parsers/

ADD configs/parse-json.conf /fluent-bit/configs/
ADD configs/minimize-log-loss.conf /fluent-bit/configs/

FROM amazonlinux:latest
RUN yum upgrade -y \
    && yum install -y openssl-devel \
          cyrus-sasl-devel \
          pkgconfig \
          systemd-devel \
          zlib-devel \
          nc

COPY --from=builder /fluent-bit /fluent-bit
COPY --from=aws-fluent-bit-plugins /kinesis-streams/bin/kinesis.so /fluent-bit/kinesis.so
COPY --from=aws-fluent-bit-plugins /kinesis-firehose/bin/firehose.so /fluent-bit/firehose.so
COPY --from=aws-fluent-bit-plugins /cloudwatch/bin/cloudwatch.so /fluent-bit/cloudwatch.so
RUN mkdir -p /fluent-bit/licenses/fluent-bit
RUN mkdir -p /fluent-bit/licenses/firehose
RUN mkdir -p /fluent-bit/licenses/cloudwatch
RUN mkdir -p /fluent-bit/licenses/kinesis
COPY THIRD-PARTY /fluent-bit/licenses/fluent-bit/
COPY --from=aws-fluent-bit-plugins /kinesis-firehose/THIRD-PARTY \
    /kinesis-firehose/LICENSE \
    /fluent-bit/licenses/firehose/
COPY --from=aws-fluent-bit-plugins /cloudwatch/THIRD-PARTY \
    /cloudwatch/LICENSE \
    /fluent-bit/licenses/cloudwatch/
COPY --from=aws-fluent-bit-plugins /kinesis-streams/THIRD-PARTY \
    /kinesis-streams/LICENSE \
    /fluent-bit/licenses/kinesis/
COPY AWS_FOR_FLUENT_BIT_VERSION /AWS_FOR_FLUENT_BIT_VERSION

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Optional Metrics endpoint
EXPOSE 2020

# Entry point
CMD /entrypoint.sh
