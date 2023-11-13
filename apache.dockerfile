###### Base stage ######
FROM ubuntu:20.04 AS base
ENV DEBIAN_FRONTEND=noninteractive

# Enable manuals (man pages)
RUN rm /etc/dpkg/dpkg.cfg.d/excludes && \
    apt update && \
    apt install -y man-db less && \
    mv /usr/bin/man.REAL /usr/bin/man

# Download prerequisites, and remove default Apache2 site
RUN apt update && apt install -y \
        apache2 \
        curl \
        git \
        software-properties-common \
        sudo \
        vim \
        mariadb-client \
        xz-utils && \
    rm /etc/apache2/sites-enabled/* && \
    rm /etc/apache2/sites-available/*

# Add PHP ppa and install PHP
ENV PHP_VER='8.1'
RUN add-apt-repository -y ppa:ondrej/php && apt update && \
    apt install -y php$PHP_VER libapache2-mod-php$PHP_VER

# Install most available php modules for this version.
#   awk to create a clean list of package names matching the regex.
#   sed to remove unwanted packages.
RUN apt-cache search ^php$PHP_VER-.* | awk '{print $1}' > /srv/E4Q && \
    sed -i '/.*gmagick.*/d' /srv/E4Q && \
    sed -i '/.*yac.*/d' /srv/E4Q && \
    sed -i '/.*phalcon.*/d' /srv/E4Q && \
    apt install -y $(cat /srv/E4Q) && \
    rm /srv/E4Q

# Install Node.js for npm
ENV NODE_VER='v16.14.2'
RUN mkdir -p /srv/nodejs/ && cd /srv/nodejs/ && \
    mkdir -p /node/ && \
    curl -L https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-x64.tar.xz > node-$NODE_VER-linux-x64.tar.xz && \
    tar -xf node-$NODE_VER-linux-x64.tar.xz --strip-components 1 && \
    cp -r ./bin/* /usr/bin/ && \
    cp -r ./include/* /usr/include/ && \
    cp -r ./lib/* /usr/lib/ && \
    cp -r ./share/* /usr/share/ && \
    rm -r /srv/nodejs/

# Install Composer (latest)
RUN mkdir -p /srv/composer/ && cd /srv/composer/ && \
    curl -L https://getcomposer.org/installer > composer-setup.php && \
    php composer-setup.php && \
    mv composer.phar /usr/local/bin/composer && \
    rm -r /srv/composer/

# Enable Apache2 modules
RUN a2enmod rewrite && \
    a2enmod headers && \
    a2enmod remoteip

WORKDIR /todo
EXPOSE 80
STOPSIGNAL SIGKILL

# Configure php.ini
#   session.sid_length:      Length of the string used as the session token in cookies. Set to double the default length.
#   session.gc_maxlifetime:  Time in seconds before the session expires server-side.
#   session.cookie_lifetime: Time in seconds before the session cookie expires client-side.
#   session.gc_probability:  How frequently garbage collection runs on sessions (to delete old sessions). Disable because Redis handles this automatically with ttl.
#   session.cache_limiter:   Set to nothing to avoid setting cache headers. Let reverse proxy handle cache-control headers.
ENV PHP_INI_ALL=/etc/php/$PHP_VER/*/php.ini
RUN sed -i 's/.\?session\.name\s\?=.*/session.name = sid/g'                              $PHP_INI_ALL && \
    sed -i 's/.\?session\.sid_length\s\?=.*/session.sid_length = 64/g'                   $PHP_INI_ALL && \
    sed -i 's/.\?session\.gc_maxlifetime\s\?=.*/session.gc_maxlifetime = ${SESS_TTL}/g'  $PHP_INI_ALL && \
    sed -i 's/.\?session\.cookie_lifetime\s\?=.*/session.cookie_lifetime = 315360000/g'  $PHP_INI_ALL && \
    sed -i 's/.\?session\.gc_probability\s\?=.*/session.gc_probability = 0/g'            $PHP_INI_ALL && \
    sed -i 's/.\?session\.save_handler\s\?=.*/session.save_handler = ${SESS_HANDLER}/g'  $PHP_INI_ALL && \
    sed -i 's/.\?session\.save_path\s\?=.*/session.save_path = ${SESS_PATH}/g'           $PHP_INI_ALL && \
    sed -i 's/.\?session\.cache_limiter\s\?=.*/session.cache_limiter = /g'               $PHP_INI_ALL && \
    sed -i 's/.\?memory_limit\s\?=.*/memory_limit = 10G/g'                               $PHP_INI_ALL && \
    sed -i 's/.\?max_execution_time\s\?=.*/max_execution_time = 86400/g'                 $PHP_INI_ALL && \
    sed -i 's/.\?upload_max_filesize\s\?=.*/upload_max_filesize = 1G/g'                  $PHP_INI_ALL && \
    sed -i 's/.\?post_max_size\s\?=.*/post_max_size = 1G/g'                              $PHP_INI_ALL

# Copy Apache2 config
COPY [".docker/apache.conf", "/etc/apache2/sites-enabled/"]

# Point the /usr/bin/php link (i.e. the "php" command) to the correct version of the php binary. Wrong version can affect php cli apps such as Phinx.
RUN update-alternatives --set php /usr/bin/php$PHP_VER

# Set uid and gid for Apache's www-data user
RUN usermod -u 1400 www-data && \
    groupmod -g 1400 www-data




###### Development stage ######
FROM base AS dev

RUN printf "\nalias sa='/usr/sbin/apache2ctl -D FOREGROUND'" >> ~/.bashrc

# Configure XDebug for remote debugging
ENV PHP_INI_APACHE=/etc/php/$PHP_VER/apache2/php.ini
RUN printf "xdebug.mode=debug\n"                >> $PHP_INI_APACHE && \
    printf "xdebug.log_level=0\n"               >> $PHP_INI_APACHE && \
    printf "xdebug.start_with_request=true\n"   >> $PHP_INI_APACHE && \
    printf "xdebug.discover_client_host=true\n" >> $PHP_INI_APACHE

# Foreground process
CMD ["tail", "-f", "/dev/null"]




###### Release stage ######
FROM base AS release

# Copy app files to /rep/
COPY [".bowerrc", "yii", "requirements", "codeception.yml", "/todo/"]
COPY ["assets/", "/todo/assets/"]
COPY ["commands/", "/todo/commands/"]
COPY ["config/", "/todo/config/"]
COPY ["controllers/", "/todo/controllers/"]
COPY ["mail/", "/todo/mail/"]
COPY ["models/", "/todo/models/"]
COPY ["views/", "/todo/views/"]
COPY ["web/", "/todo/web/"]
COPY ["widgets/", "/todo/widgets/"]

# Get Composer packages
COPY ["composer.json", "composer.lock", "/todo/"]
RUN composer install

# Foreground process
CMD ["tail", "-f", "/dev/null"]

# # Create an empty TypeScript entry point file because the Node.js backend runs in a separate container but webpack still needs to build
# RUN mkdir /rep/nodeapp && touch /rep/nodeapp/main.ts

# # Get npm packages
# COPY ["package.json", "package-lock.json", "/rep/"]
# RUN npm install

# # Build/Bundle and set Apache as owner of /rep/static/
# RUN npm run build && chown -R www-data:www-data ./static

# # Foreground process
# CMD ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]
