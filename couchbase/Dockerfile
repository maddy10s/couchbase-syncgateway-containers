FROM couchbase/server:community-7.1.1

LABEL MAINTAINER="smadankumar@yahoo.in"

ENV ADMIN_LOGIN $ADMIN_LOGIN
ENV ADMIN_PASSWORD $ADMIN_PASSWORD

# Curl is needed as a diagnostic tool during build.
RUN apt-get update && \
    apt-get install -yq curl && \
    apt-get autoremove && \
    apt-get clean


COPY init.sh /
RUN chmod +x /init.sh

ENTRYPOINT ["/init.sh"]

#8091-8093,11207,11209,11210,11211,11214,11215,18091,18092,4396,21100-21199
EXPOSE 8091
