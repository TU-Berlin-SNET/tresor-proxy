FROM dockerfile/ubuntu

# Copy Proxy files
ADD . /root/tresor-proxy
WORKDIR /root/tresor-proxy

# Install Ruby 2.0 using rvm and install gems of proxy
RUN curl -sSL https://get.rvm.io | bash -s stable --ruby=2.0 &&\
    /bin/bash -c "source /usr/local/rvm/scripts/rvm && bundle install" &&\
    chmod +x /root/tresor-proxy/bin/proxy_docker.sh

# Run Proxy
CMD ["/bin/bash", "-c"]
ENTRYPOINT ["/root/tresor-proxy/bin/proxy_docker.sh"]